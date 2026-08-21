-- Phase 9 capability IAE-003 (Dashboard Builder, Prompt 331, CG-S14-IAE-003)
-- A real, first-ever tenant-configurable dashboard canvas -- every prior
-- "dashboard" in this repository (Commercial COM-158, Operations OPS-183,
-- Finance FIN-213, Procurement) is a fixed, code-defined page showing a fixed
-- widget set. This migration builds the widget/layout/version/publish/
-- rollback mechanism Prompt 331 asks for, on top of (never duplicating) the
-- IAE-002 report catalog -- a widget always binds to an existing, active
-- `app.report_types` code; there is no raw-SQL widget shape (Prompt 331
-- business rule §24: "not raw SQL for tenants").
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **`app.entitlement_modules`/`app.permissions` already seeded a real `REP`
--   module (`PLT-106`/`PLT-111`, Phase 1) with `View`/`Export`/`Print`/
--   `Configure` actions, never consumed by any Phase 1-8 capability** (IAE-002
--   reused `COM:Export` for its own `cancel_report_run`, the only pre-existing
--   choice available to a Commercial-scoped report engine at the time it was
--   authored, now a disclosed, non-blocking Tier C note for Batch 1's own
--   review -- see `docs/build-log/phase-09/IAE-330.md`). `REP:Configure` gates
--   every mutation this migration adds; it is this repository's own first
--   real consumer of the `REP` module, not this checkpoint's invention.
-- * **Version/publish/rollback mirrors IAE-002's own `report_type_versions`
--   shape**: `app.tenant_dashboard_versions` is append-only; a dashboard's own
--   `current_version_id` is the only thing "current" means, and it only ever
--   points at a `published` version -- a fresh `draft` version is created
--   automatically at publish time (copying the just-published version's own
--   widgets) so editing can continue without ever mutating a published
--   snapshot in place (Prompt 331 business rule §24: "immutable snapshots").
--   Rollback moves `current_version_id` to an older `published` version; it
--   never deletes or rewrites any version row.
-- * **A widget is a binding, never a query.** `app.tenant_dashboard_widgets.
--   report_type_code` is a live FK into `app.report_types`; `add_dashboard_widget`
--   rejects an unknown or `retired` code and validates `parameter_overrides`
--   against that report's own `parameter_schema` by reusing IAE-002's
--   `app.validate_report_parameters` directly -- never a second validator.
--   Actually rendering a widget's own data still goes through the existing
--   `app.record_report_run`/domain `get_*` function pair, unchanged; this
--   migration adds no new data-query SQL at all.
-- * **Visibility is tenant-wide, mirroring `app.report_runs`' own precedent**
--   ("who ran which report, when, is management visibility, not per-owner
--   private data" -- the identical reasoning applies to "what dashboards this
--   tenant has configured"). `REP:Configure` gates every create/edit/publish/
--   rollback action; `REP:View`'s own first real consumer is left to a later
--   Phase 9 capability (disclosed, not fabricated here) rather than
--   retrofitting an artificial draft/published visibility split this
--   checkpoint's own scope does not need.
-- * Per `ERR-2026-004`: explicit `revoke execute on all functions in schema
--   app from public` before any grant, the standing convention since `PLT-118`.
-- * **ATW-032/C-13 compliance built in from the start** (a lesson IAE-002's
--   own Tier B review surfaced): every side-effecting function below calls
--   `app.assert_actor_is_session_identity` as its first statement.
-- * **C-04 compliance built in from the start**: `publish_tenant_dashboard_version`
--   and `rollback_tenant_dashboard` both lock the `tenant_dashboards` row
--   `for update` before deciding.

create table app.tenant_dashboards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  name text not null,
  description text not null default '',
  status text not null default 'draft',
  current_version_id uuid,
  created_by_auth_user_id uuid not null references auth.users (id),
  created_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_dashboards_status_check check (status in ('draft', 'published', 'archived')),
  constraint tenant_dashboards_name_check check (length(trim(name)) > 0)
);

comment on table app.tenant_dashboards is
  'IAE-003: one row per tenant-configured dashboard. current_version_id is null until the first publish; status=draft/published/archived tracks whether any version has ever been published, not the current draft-in-progress state (a published dashboard always has an editable next draft version too).';

create index tenant_dashboards_tenant_idx on app.tenant_dashboards (tenant_id, updated_at desc);

create table app.tenant_dashboard_versions (
  id uuid primary key default gen_random_uuid(),
  dashboard_id uuid not null references app.tenant_dashboards (id),
  version_number integer not null,
  layout jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  published_by_auth_user_id uuid references auth.users (id),
  published_by text,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  constraint tenant_dashboard_versions_version_check check (version_number > 0),
  constraint tenant_dashboard_versions_status_check check (status in ('draft', 'published', 'superseded')),
  constraint tenant_dashboard_versions_layout_check check (jsonb_typeof(layout) = 'object'),
  constraint tenant_dashboard_versions_unique unique (dashboard_id, version_number)
);

comment on table app.tenant_dashboard_versions is
  'IAE-003: append-only, mirrors app.report_type_versions exactly. layout is a free-form grid-position hint (columns/breakpoints), never a query -- the widgets table is the real content. Exactly one draft and at most one published row may exist per dashboard at a time, enforced in application logic (app.publish_tenant_dashboard_version), the same convention app.report_type_versions leaves to app.publish_report_type_version.';

create index tenant_dashboard_versions_dashboard_idx on app.tenant_dashboard_versions (dashboard_id, version_number desc);

create table app.tenant_dashboard_widgets (
  id uuid primary key default gen_random_uuid(),
  dashboard_version_id uuid not null references app.tenant_dashboard_versions (id),
  report_type_code text not null references app.report_types (code),
  title text not null,
  position jsonb not null default '{}'::jsonb,
  parameter_overrides jsonb not null default '{}'::jsonb,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint tenant_dashboard_widgets_title_check check (length(trim(title)) > 0),
  constraint tenant_dashboard_widgets_position_check check (jsonb_typeof(position) = 'object'),
  constraint tenant_dashboard_widgets_params_check check (jsonb_typeof(parameter_overrides) = 'object')
);

comment on table app.tenant_dashboard_widgets is
  'IAE-003: a widget is a binding to an existing, approved app.report_types code plus a position hint and parameter overrides -- never a raw query (Prompt 331 §24). parameter_overrides is validated against that report''s own current parameter_schema at add-time via app.validate_report_parameters (IAE-002), reused directly.';

create index tenant_dashboard_widgets_version_idx on app.tenant_dashboard_widgets (dashboard_version_id, display_order);

alter table app.tenant_dashboards add constraint tenant_dashboards_current_version_fk
  foreign key (current_version_id) references app.tenant_dashboard_versions (id);

create function app.touch_tenant_dashboard_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger tenant_dashboards_touch_row
  before update on app.tenant_dashboards
  for each row
  execute function app.touch_tenant_dashboard_row();

create function app.create_tenant_dashboard_draft(
  p_tenant_id uuid,
  p_name text,
  p_description text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_dashboards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_dashboard app.tenant_dashboards;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'dashboard_name_required: name must not be empty' using errcode = 'check_violation';
  end if;

  insert into app.tenant_dashboards (tenant_id, name, description, created_by_auth_user_id, created_by)
  values (p_tenant_id, p_name, coalesce(p_description, ''), p_actor_auth_user_id, p_actor_label)
  returning * into v_dashboard;

  insert into app.tenant_dashboard_versions (dashboard_id, version_number, layout, status)
  values (v_dashboard.id, 1, '{}'::jsonb, 'draft');

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_tenant_dashboard_draft',
    'app.tenant_dashboards', v_dashboard.id, 'success', null, null, to_jsonb(v_dashboard)
  );

  return v_dashboard;
end;
$$;

comment on function app.create_tenant_dashboard_draft is
  'IAE-003: REP:Configure-gated. Creates the dashboard row plus its own version-1 draft in one transaction -- a dashboard never exists without at least one version.';

create function app.add_dashboard_widget(
  p_dashboard_version_id uuid,
  p_report_type_code text,
  p_title text,
  p_position jsonb,
  p_parameter_overrides jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_dashboard_widgets
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.tenant_dashboard_versions;
  v_dashboard app.tenant_dashboards;
  v_type app.report_types;
  v_decision app.rbac_decision;
  v_widget app.tenant_dashboard_widgets;
  v_next_order integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_version from app.tenant_dashboard_versions where id = p_dashboard_version_id;
  if not found then
    raise exception 'dashboard_version_not_found: %', p_dashboard_version_id using errcode = 'no_data_found';
  end if;

  select * into v_dashboard from app.tenant_dashboards where id = v_version.dashboard_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dashboard.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dashboard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'dashboard_version_not_editable: version % is % (only a draft version accepts widget changes)', p_dashboard_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and cannot be added to a dashboard', p_report_type_code using errcode = 'check_violation';
  end if;

  if not app.validate_report_parameters(v_type.parameter_schema, coalesce(p_parameter_overrides, '{}'::jsonb)) then
    raise exception 'widget_unsafe_parameters: parameter_overrides failed structural or schema validation'
      using errcode = 'check_violation';
  end if;

  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'widget_title_required: title must not be empty' using errcode = 'check_violation';
  end if;

  select coalesce(max(display_order), -1) + 1 into v_next_order
  from app.tenant_dashboard_widgets where dashboard_version_id = p_dashboard_version_id;

  insert into app.tenant_dashboard_widgets (
    dashboard_version_id, report_type_code, title, position, parameter_overrides, display_order
  ) values (
    p_dashboard_version_id, p_report_type_code, p_title, coalesce(p_position, '{}'::jsonb), coalesce(p_parameter_overrides, '{}'::jsonb), v_next_order
  )
  returning * into v_widget;

  perform app.capture_audit_event(
    v_dashboard.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_dashboard_widget',
    'app.tenant_dashboard_widgets', v_widget.id, 'success', null, null,
    jsonb_build_object('dashboard_version_id', p_dashboard_version_id, 'report_type_code', p_report_type_code)
  );

  return v_widget;
end;
$$;

comment on function app.add_dashboard_widget is
  'IAE-003: REP:Configure-gated, draft-only. Rejects an unknown/retired report_type_code and validates parameter_overrides via app.validate_report_parameters (IAE-002, reused directly) against that report''s own current parameter_schema.';

create function app.remove_dashboard_widget(
  p_widget_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_widget app.tenant_dashboard_widgets;
  v_version app.tenant_dashboard_versions;
  v_dashboard app.tenant_dashboards;
  v_decision app.rbac_decision;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_widget from app.tenant_dashboard_widgets where id = p_widget_id;
  if not found then
    raise exception 'dashboard_widget_not_found: %', p_widget_id using errcode = 'no_data_found';
  end if;

  select * into v_version from app.tenant_dashboard_versions where id = v_widget.dashboard_version_id;
  select * into v_dashboard from app.tenant_dashboards where id = v_version.dashboard_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dashboard.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dashboard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'dashboard_version_not_editable: version % is % (only a draft version accepts widget changes)', v_version.id, v_version.status
      using errcode = 'check_violation';
  end if;

  delete from app.tenant_dashboard_widgets where id = p_widget_id;

  perform app.capture_audit_event(
    v_dashboard.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_dashboard_widget',
    'app.tenant_dashboard_widgets', p_widget_id, 'success', null, null,
    jsonb_build_object('dashboard_version_id', v_widget.dashboard_version_id, 'report_type_code', v_widget.report_type_code)
  );
end;
$$;

comment on function app.remove_dashboard_widget is
  'IAE-003: REP:Configure-gated, draft-only, mirrors app.add_dashboard_widget''s own gate exactly. A real DELETE is safe here (unlike a report_runs/report_type_versions row) because a draft version''s own widget list is not yet evidence of anything published.';

create function app.publish_tenant_dashboard_version(
  p_dashboard_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_dashboard_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_dashboard app.tenant_dashboards;
  v_decision app.rbac_decision;
  v_draft app.tenant_dashboard_versions;
  v_next_version integer;
  v_new_draft app.tenant_dashboard_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_dashboard from app.tenant_dashboards where id = p_dashboard_id for update;
  if not found then
    raise exception 'dashboard_not_found: %', p_dashboard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dashboard.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dashboard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_draft from app.tenant_dashboard_versions
  where dashboard_id = p_dashboard_id and status = 'draft'
  order by version_number desc limit 1;
  if not found then
    raise exception 'dashboard_no_draft_version: dashboard % has no draft version to publish', p_dashboard_id using errcode = 'no_data_found';
  end if;

  if not exists (select 1 from app.tenant_dashboard_widgets where dashboard_version_id = v_draft.id) then
    raise exception 'dashboard_empty_version: a version with zero widgets cannot be published' using errcode = 'check_violation';
  end if;

  update app.tenant_dashboard_versions
  set status = 'published', published_by_auth_user_id = p_actor_auth_user_id, published_by = p_actor_label, published_at = now()
  where id = v_draft.id;

  update app.tenant_dashboards
  set status = 'published', current_version_id = v_draft.id
  where id = p_dashboard_id;

  v_next_version := v_draft.version_number + 1;
  insert into app.tenant_dashboard_versions (dashboard_id, version_number, layout, status)
  values (p_dashboard_id, v_next_version, v_draft.layout, 'draft')
  returning * into v_new_draft;

  insert into app.tenant_dashboard_widgets (dashboard_version_id, report_type_code, title, position, parameter_overrides, display_order)
  select v_new_draft.id, report_type_code, title, position, parameter_overrides, display_order
  from app.tenant_dashboard_widgets
  where dashboard_version_id = v_draft.id;

  perform app.capture_audit_event(
    v_dashboard.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_tenant_dashboard_version',
    'app.tenant_dashboard_versions', v_draft.id, 'success', null, null,
    jsonb_build_object('dashboard_id', p_dashboard_id, 'version_number', v_draft.version_number)
  );

  select * into v_draft from app.tenant_dashboard_versions where id = v_draft.id;
  return v_draft;
end;
$$;

comment on function app.publish_tenant_dashboard_version is
  'IAE-003: REP:Configure-gated. Locks the dashboard row for update before deciding (C-04). Publishes the current draft (rejecting an empty one), points current_version_id at it, then opens a fresh draft version copying the just-published widgets so editing continues without ever mutating a published snapshot in place.';

create function app.rollback_tenant_dashboard(
  p_dashboard_id uuid,
  p_target_version_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.tenant_dashboards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_dashboard app.tenant_dashboards;
  v_decision app.rbac_decision;
  v_target app.tenant_dashboard_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_dashboard from app.tenant_dashboards where id = p_dashboard_id for update;
  if not found then
    raise exception 'dashboard_not_found: %', p_dashboard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dashboard.tenant_id, 'REP', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dashboard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_target from app.tenant_dashboard_versions
  where id = p_target_version_id and dashboard_id = p_dashboard_id and status = 'published';
  if not found then
    raise exception 'dashboard_target_version_invalid: % is not a published version of dashboard %', p_target_version_id, p_dashboard_id
      using errcode = 'check_violation';
  end if;

  update app.tenant_dashboards set current_version_id = p_target_version_id where id = p_dashboard_id
  returning * into v_dashboard;

  perform app.capture_audit_event(
    v_dashboard.tenant_id, p_actor_auth_user_id, p_actor_label, 'rollback_tenant_dashboard',
    'app.tenant_dashboards', p_dashboard_id, 'success', null, null,
    jsonb_build_object('target_version_id', p_target_version_id, 'target_version_number', v_target.version_number)
  );

  return v_dashboard;
end;
$$;

comment on function app.rollback_tenant_dashboard is
  'IAE-003: REP:Configure-gated. Locks the dashboard row for update before deciding (C-04). Points current_version_id at an older PUBLISHED version only -- never a draft, never a delete/rewrite of any version row.';

alter table app.tenant_dashboards enable row level security;
alter table app.tenant_dashboard_versions enable row level security;
alter table app.tenant_dashboard_widgets enable row level security;

-- CG-S10-ATW-032/ISS-2026-010 default-deny (`20260730560000`'s own ratified
-- convention, standing for every migration from that point on): a SELECT
-- policy that tests plain tenant membership and nothing else also admits a
-- `customer_user`-layer principal, who satisfies `has_active_tenant_membership`
-- exactly like an ordinary org_user. The layer check is inserted BESIDE each
-- membership call (never appended outside an `EXISTS`, where the joined
-- alias would be out of scope) so a raw Supabase client under that layer
-- cannot read tenant dashboard configuration -- which report codes/parameters
-- a tenant has chosen to surface -- with no portal code involved.
create policy tenant_dashboards_select_scoped on app.tenant_dashboards
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy tenant_dashboard_versions_select_scoped on app.tenant_dashboard_versions
  for select to authenticated
  using (exists (
    select 1 from app.tenant_dashboards d
    where d.id = tenant_dashboard_versions.dashboard_id
      and ((app.has_active_tenant_membership(d.tenant_id) and not app.actor_holds_customer_user_layer(d.tenant_id)) or app.is_supreme_admin())
  ));

create policy tenant_dashboard_widgets_select_scoped on app.tenant_dashboard_widgets
  for select to authenticated
  using (exists (
    select 1 from app.tenant_dashboard_versions v
    join app.tenant_dashboards d on d.id = v.dashboard_id
    where v.id = tenant_dashboard_widgets.dashboard_version_id
      and ((app.has_active_tenant_membership(d.tenant_id) and not app.actor_holds_customer_user_layer(d.tenant_id)) or app.is_supreme_admin())
  ));

revoke execute on all functions in schema app from public;

grant select on app.tenant_dashboards, app.tenant_dashboard_versions, app.tenant_dashboard_widgets to authenticated, service_role;
grant insert, update, delete on app.tenant_dashboards, app.tenant_dashboard_versions, app.tenant_dashboard_widgets to service_role;

grant execute on function app.create_tenant_dashboard_draft(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.add_dashboard_widget(uuid, text, text, jsonb, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.remove_dashboard_widget(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.publish_tenant_dashboard_version(uuid, uuid, text) to authenticated, service_role;
grant execute on function app.rollback_tenant_dashboard(uuid, uuid, uuid, text) to authenticated, service_role;
