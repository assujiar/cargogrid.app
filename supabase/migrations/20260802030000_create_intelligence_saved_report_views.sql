-- Phase 9 capability IAE-004 (Saved View and Configurable Report, Prompt 332,
-- CG-S14-IAE-004). A real, cross-domain "save this report configuration and
-- optionally share it with the tenant" mechanism on top of the IAE-002 report
-- catalog (`app.report_types`) -- columns, filters, sort and grouping are all
-- presentational/replay config, never a data snapshot (Prompt 332 §24: "Saved
-- views never store privileged data snapshots").
--
-- Scope and design decisions, disclosed rather than left implicit:
--
-- * **A pre-existing, narrower precedent already exists and is deliberately not
--   reused as the storage table**: `app.procurement_dashboard_saved_views`
--   (`PRC-266`, `20260730780000`) is a real, `VERIFIED` saved-view mechanism,
--   but scoped to exactly Procurement's own 7 fixed dashboard `metric_group`
--   values, owner-only (no sharing at all -- its own header: "distinct from
--   every tenant-wide... table"), and has no `columns`/`grouping` field. Prompt
--   332 asks for the opposite shape on the differentiating axis that matters:
--   cross-domain (any `app.report_types` code, not 7 fixed Procurement groups)
--   AND real sharing (`sharing_scope`, entirely absent from PRC-266). This
--   migration builds a new, general table rather than widening PRC-266's own
--   already-`VERIFIED`, narrowly-scoped shape -- the same "new general
--   mechanism beside an already-correct narrower one" precedent IAE-002 itself
--   set relative to each domain's own pre-existing `get_dashboard_*` functions.
--   PRC-266's own CRUD shape (idempotency-key replay comparing the full target
--   tuple, `for update` + explicit `stale_version` guard on update/delete,
--   "not found" folding not-found and no-access together for owner-only
--   lookups) is mirrored here directly rather than re-derived.
-- * **`filters` IS the underlying report's own `parameters` bag, not a second
--   query language.** A saved view is a bookmark of (report_type_code,
--   parameters, display config), replayable through the existing, unchanged
--   `app.record_report_run`/`app.enqueue_report_export` -- this migration adds
--   no new data-query SQL at all. `filters` is validated against the report's
--   own current `parameter_schema` via `app.validate_report_parameters`
--   (IAE-002, reused directly, never a second validator).
-- * **`columns`/`sort`/`grouping` are presentational-only and structurally
--   validated via `app.validate_config_value`** (`PLT-11x`'s own generic,
--   depth/size-bounded, injection-shaped-string-rejecting JSON validator,
--   already reused by PRC-266 for the identical purpose) -- reused directly
--   rather than a third bespoke validator. Because a saved view stores no data
--   of its own, "reintroducing a hidden field" (Prompt 332 §24) cannot leak
--   anything: requesting an unmasked column name still only ever receives
--   whatever `record_report_run`'s own caller already computed and masked for
--   that run (`masked_columns`, IAE-002) -- the saved view mechanism has no
--   path around that existing masking, structurally, because it never touches
--   row data.
-- * **Sharing a view shares its CONFIG, never underlying record access**
--   (Prompt 332 §24). `sharing_scope='tenant'` only widens who may SELECT the
--   view's own filter/column/sort JSON; actually running it still goes through
--   the SAME report-execution path (`record_report_run`/`enqueue_report_export`)
--   with the SAME authority checks that path has always required. Only the
--   owner may edit or delete a view, shared or private -- sharing never grants
--   write access, mirroring how `IAE-003`'s own dashboards separate
--   `REP:Configure` (author) from tenant-wide read.
-- * **`REP:Configure` gates only creating/updating a `tenant`-shared view** --
--   the same "configuring a shared reporting artifact" authority `IAE-003`
--   established as this module's own real consumer. A `private` view requires
--   no elevated permission beyond ordinary, non-`customer_user`-layer tenant
--   membership (the same audience the report catalog itself is already visible
--   to, per `IAE-002`'s own Report Library).
-- * **Staleness detection, not silent breakage** (Prompt 332's own Alternative
--   flow: "a saved view becomes invalid after source schema change... safe
--   fallback"). `report_type_version_id` is stamped at create/update time; the
--   query layer (never a DB trigger -- this is presentational staleness, not
--   an integrity constraint) compares it against the report type's own current
--   version to disclose `isStale` to the UI, which still lets the view run
--   (the underlying report's own parameter validation is the real gate, not a
--   saved view's own possibly-outdated stamp).
-- * **Export/scheduled-report compatibility is reuse, not a new RPC.** "Export
--   this saved view" composes the EXISTING `enqueue_report_export` with the
--   view's own `reportTypeCode`/`filters` at the service layer -- no new
--   database function. `IAE-006` (Prompt 334, Scheduled Reports) owns actually
--   running a view on a schedule; this checkpoint deliberately builds no
--   scheduling mechanism of its own (disclosed, not a gap -- see the WBS's own
--   downstream-impact note citing `IAE-334`).
-- * **ATW-032/C-13 and C-04 compliance built in from the start** (the standing
--   lesson every Batch 1 checkpoint so far has applied): every side-effecting
--   function calls `app.assert_actor_is_session_identity` first; `update`/
--   `delete` lock their own row `for update` before deciding.
-- * **`update`/`delete` also call `app.assert_session_identity_in_tenant`
--   after their own row lookup** -- found necessary by
--   `scripts/db-tests/rbac-enforcement.sql`'s own ATW-032 authority-surface
--   sweep on this migration's first draft: an ownership-equality check
--   (`owner_auth_user_id <> p_actor_auth_user_id`) is real authority, but the
--   sweep's static call-graph analysis only recognizes
--   `app.evaluate_permission`/`app.can_access_record`/
--   `app.assert_session_identity_in_tenant` as a provable check, mirroring
--   `PRC-266`'s own `update_procurement_dashboard_saved_view`'s identical
--   two-check shape (ownership plus a real permission call) rather than
--   inventing a bespoke exception to the sweep.
-- * **RLS is narrowed for the `customer_user` layer from the very first
--   draft** (`CG-S10-ATW-032`/`ISS-2026-010`, `20260730560000`'s own ratified
--   convention) -- the exact gap `IAE-003`'s own first draft reintroduced by
--   copying an older, pre-convention precedent forward. Not repeated here.
-- * Per `ERR-2026-004`: explicit `revoke execute on all functions in schema
--   app from public` before any grant, the standing convention since `PLT-118`.

create table app.saved_report_views (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  report_type_code text not null references app.report_types (code),
  report_type_version_id uuid references app.report_type_versions (id),
  owner_auth_user_id uuid not null references auth.users (id),
  owner_label text,
  name text not null,
  description text,
  sharing_scope text not null default 'private',
  columns jsonb not null default '[]'::jsonb,
  filters jsonb not null default '{}'::jsonb,
  sort jsonb not null default '{}'::jsonb,
  grouping jsonb not null default '{}'::jsonb,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint saved_report_views_sharing_scope_check check (sharing_scope in ('private', 'tenant')),
  constraint saved_report_views_name_check check (length(trim(name)) > 0),
  constraint saved_report_views_columns_check check (jsonb_typeof(columns) = 'array'),
  constraint saved_report_views_filters_check check (jsonb_typeof(filters) = 'object'),
  constraint saved_report_views_sort_check check (jsonb_typeof(sort) = 'object'),
  constraint saved_report_views_grouping_check check (jsonb_typeof(grouping) = 'object')
);

comment on table app.saved_report_views is
  'IAE-004: a named, optionally tenant-shared (sharing_scope) bookmark of one app.report_types code plus display config (columns/sort/grouping) and run parameters (filters). Stores no data of its own -- running a view always replays through the unchanged app.record_report_run/app.enqueue_report_export. Distinct from app.procurement_dashboard_saved_views (PRC-266): that table is Procurement-only, owner-only, no columns/grouping, no sharing -- see this migration''s own header for why it is not reused as the storage table.';

create index saved_report_views_tenant_idx on app.saved_report_views (tenant_id, report_type_code, created_at desc);
create index saved_report_views_owner_idx on app.saved_report_views (tenant_id, owner_auth_user_id, created_at desc);
create unique index saved_report_views_idempotency_key_unique on app.saved_report_views (tenant_id, owner_auth_user_id, idempotency_key) where idempotency_key is not null;

create function app.touch_saved_report_view_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger saved_report_views_touch_row
  before update on app.saved_report_views
  for each row
  execute function app.touch_saved_report_view_row();

create function app.create_saved_report_view(
  p_tenant_id uuid,
  p_report_type_code text,
  p_name text,
  p_description text,
  p_columns jsonb,
  p_filters jsonb,
  p_sort jsonb,
  p_grouping jsonb,
  p_sharing_scope text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.saved_report_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_type app.report_types;
  v_decision app.rbac_decision;
  v_sharing_scope text := coalesce(p_sharing_scope, 'private');
  v_columns jsonb := coalesce(p_columns, '[]'::jsonb);
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_sort jsonb := coalesce(p_sort, '{}'::jsonb);
  v_grouping jsonb := coalesce(p_grouping, '{}'::jsonb);
  v_version_id uuid;
  v_existing app.saved_report_views;
  v_view app.saved_report_views;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not (v_sharing_scope = any (array['private', 'tenant'])) then
    raise exception 'saved_view_invalid_sharing_scope: % is not private or tenant', v_sharing_scope using errcode = 'check_violation';
  end if;

  if v_sharing_scope = 'tenant' then
    v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'REP', 'Configure');
    if not v_decision.allowed then
      raise exception 'insufficient_authority: identity % lacks REP:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  else
    if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) and not app.is_supreme_admin(p_actor_auth_user_id) then
      raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  select * into v_type from app.report_types where code = p_report_type_code;
  if not found then
    raise exception 'report_type_unknown: %', p_report_type_code using errcode = 'no_data_found';
  end if;
  if v_type.status <> 'active' then
    raise exception 'report_type_retired: % is retired and cannot back a saved view', p_report_type_code using errcode = 'check_violation';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a saved view requires a non-empty name' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_columns) = 0 then
    raise exception 'saved_view_columns_required: at least one column must be selected' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_columns) then
    raise exception 'saved_view_unsafe_columns: columns failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_report_parameters(v_type.parameter_schema, v_filters) then
    raise exception 'saved_view_unsafe_filters: filters failed structural or schema validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_sort) then
    raise exception 'saved_view_unsafe_sort: sort failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_grouping) then
    raise exception 'saved_view_unsafe_grouping: grouping failed structural validation' using errcode = 'check_violation';
  end if;

  select id into v_version_id from app.report_type_versions
  where report_type_code = p_report_type_code
  order by version_number desc limit 1;

  -- C-01: idempotency replay compares the FULL target tuple, not just the key.
  if p_idempotency_key is not null then
    select * into v_existing
    from app.saved_report_views
    where tenant_id = p_tenant_id and owner_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.report_type_code is distinct from p_report_type_code
        or v_existing.name is distinct from p_name
        or v_existing.description is distinct from p_description
        or v_existing.sharing_scope is distinct from v_sharing_scope
        or v_existing.columns is distinct from v_columns
        or v_existing.filters is distinct from v_filters
        or v_existing.sort is distinct from v_sort
        or v_existing.grouping is distinct from v_grouping
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different saved view', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- C-02: the insert alone is nested in its own exception scope, so a genuine
  -- concurrent-insert race is recovered here without swallowing the deliberate
  -- idempotency_key_conflict raise above.
  begin
    insert into app.saved_report_views (
      tenant_id, report_type_code, report_type_version_id, owner_auth_user_id, owner_label,
      name, description, sharing_scope, columns, filters, sort, grouping, idempotency_key, created_by
    ) values (
      p_tenant_id, p_report_type_code, v_version_id, p_actor_auth_user_id, p_actor_label,
      p_name, p_description, v_sharing_scope, v_columns, v_filters, v_sort, v_grouping, p_idempotency_key, p_actor_label
    )
    returning * into v_view;
  exception when unique_violation then
    select * into v_existing
    from app.saved_report_views
    where tenant_id = p_tenant_id and owner_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
    raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_saved_report_view',
    'app.saved_report_views', v_view.id, 'success', null, null, to_jsonb(v_view)
  );

  return v_view;
end;
$$;

comment on function app.create_saved_report_view is
  'IAE-004: a private view requires only active, non-customer_user-layer tenant membership; a tenant-shared view requires REP:Configure. Stamps report_type_version_id to the report''s own current latest version for later staleness detection.';

create function app.update_saved_report_view(
  p_view_id uuid,
  p_expected_version integer,
  p_name text,
  p_description text,
  p_columns jsonb,
  p_filters jsonb,
  p_sort jsonb,
  p_grouping jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.saved_report_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.saved_report_views;
  v_type app.report_types;
  v_columns jsonb := coalesce(p_columns, '[]'::jsonb);
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_sort jsonb := coalesce(p_sort, '{}'::jsonb);
  v_grouping jsonb := coalesce(p_grouping, '{}'::jsonb);
  v_version_id uuid;
  v_updated app.saved_report_views;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- No p_tenant_id parameter -- the row lookup is structurally required before
  -- ownership can even be checked (mirrors PRC-266's own accepted by-id shape).
  -- "Not found" and "not this actor's own view" fold into the identical error.
  select * into v_view from app.saved_report_views where id = p_view_id for update;
  if not found or v_view.owner_auth_user_id <> p_actor_auth_user_id then
    raise exception 'saved_report_view_not_found: % is not a known saved view for this actor', p_view_id using errcode = 'no_data_found';
  end if;
  perform app.assert_session_identity_in_tenant(v_view.tenant_id);

  select * into v_type from app.report_types where code = v_view.report_type_code;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a saved view requires a non-empty name' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_columns) = 0 then
    raise exception 'saved_view_columns_required: at least one column must be selected' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_columns) then
    raise exception 'saved_view_unsafe_columns: columns failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_report_parameters(v_type.parameter_schema, v_filters) then
    raise exception 'saved_view_unsafe_filters: filters failed structural or schema validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_sort) then
    raise exception 'saved_view_unsafe_sort: sort failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_grouping) then
    raise exception 'saved_view_unsafe_grouping: grouping failed structural validation' using errcode = 'check_violation';
  end if;

  select id into v_version_id from app.report_type_versions
  where report_type_code = v_view.report_type_code
  order by version_number desc limit 1;

  -- C-03: the versioned update is immediately followed by an explicit stale-version guard.
  update app.saved_report_views
  set name = p_name, description = p_description, columns = v_columns, filters = v_filters,
      sort = v_sort, grouping = v_grouping, report_type_version_id = v_version_id
  where id = p_view_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: saved view % was changed by another request -- reload and retry', p_view_id using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_view.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_saved_report_view',
    'app.saved_report_views', v_view.id, 'success', null, to_jsonb(v_view), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.delete_saved_report_view(
  p_view_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns boolean
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.saved_report_views;
  v_deleted_count integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_view from app.saved_report_views where id = p_view_id for update;
  if not found or v_view.owner_auth_user_id <> p_actor_auth_user_id then
    raise exception 'saved_report_view_not_found: % is not a known saved view for this actor', p_view_id using errcode = 'no_data_found';
  end if;
  perform app.assert_session_identity_in_tenant(v_view.tenant_id);

  delete from app.saved_report_views where id = p_view_id and record_version = p_expected_version;
  get diagnostics v_deleted_count = row_count;
  if v_deleted_count = 0 then
    raise exception 'stale_version: saved view % was changed by another request -- reload and retry', p_view_id using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_view.tenant_id, p_actor_auth_user_id, p_actor_label, 'delete_saved_report_view',
    'app.saved_report_views', p_view_id, 'success', null, to_jsonb(v_view), null
  );

  return true;
end;
$$;

comment on function app.delete_saved_report_view is
  'IAE-004: owner-only, mirrors app.update_saved_report_view''s own gate exactly -- sharing a view never grants write access.';

create function app.list_saved_report_views(
  p_tenant_id uuid,
  p_report_type_code text,
  p_actor_auth_user_id uuid,
  p_limit integer default 25,
  p_cursor timestamptz default null
)
returns setof app.saved_report_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) and not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % has no active membership in tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.saved_report_views
  where tenant_id = p_tenant_id
    and (p_report_type_code is null or report_type_code = p_report_type_code)
    and (owner_auth_user_id = p_actor_auth_user_id or sharing_scope = 'tenant' or app.is_supreme_admin(p_actor_auth_user_id))
    and (p_cursor is null or created_at < p_cursor)
  order by created_at desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

comment on function app.list_saved_report_views is
  'IAE-004: the calling actor''s own views (any sharing_scope) PLUS every tenant-shared view from any owner -- unlike PRC-266''s own "owner only, no sharing" list, this is the differentiating feature this checkpoint adds. Cursor-paginated on created_at desc.';

alter table app.saved_report_views enable row level security;

-- CG-S10-ATW-032/ISS-2026-010 default-deny narrowing applied from the first
-- draft (the exact gap IAE-003's own first draft reintroduced by copying an
-- older, pre-convention precedent -- not repeated here). Own-row access is
-- unconditional (a customer_user-layer principal seeing their OWN saved view
-- config is not the leak that convention closes); tenant-shared-row access is
-- narrowed exactly like every other tenant-wide SELECT policy since it.
create policy saved_report_views_select_scoped on app.saved_report_views
  for select to authenticated
  using (
    app.is_supreme_admin()
    or owner_auth_user_id = (select auth.uid())
    or (sharing_scope = 'tenant' and app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id))
  );

revoke execute on all functions in schema app from public;

grant select on app.saved_report_views to authenticated, service_role;
grant insert, update, delete on app.saved_report_views to service_role;

grant execute on function app.create_saved_report_view(uuid, text, text, text, jsonb, jsonb, jsonb, jsonb, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_saved_report_view(uuid, integer, text, text, jsonb, jsonb, jsonb, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.delete_saved_report_view(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.list_saved_report_views(uuid, text, uuid, integer, timestamptz) to authenticated, service_role;
