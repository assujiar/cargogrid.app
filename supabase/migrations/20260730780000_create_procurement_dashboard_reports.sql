-- Procurement capability PRC-266 (Procurement Dashboard and Reports, CG-S11-PRC-017).
-- First (and only) prompt of batch 5 ("lanjut prompt 266 sd 270") of the batched review
-- cadence (ADR-0021), built directly on the already-VERIFIED PRC-251..265 (vendor
-- identity/lifecycle, compliance, rates, sourcing, RFQ, comparison, approval, PO,
-- contract, capacity, assignment, performance, invoice matching).
--
-- A permission-safe, source-reconciled READ layer over the 16 already-VERIFIED
-- Procurement/Vendor capabilities. Zero INSERT/UPDATE/DELETE against any pre-existing
-- app.vendor_*/app.rfq_*/app.purchase_order_*/app.sourcing_*/app.procurement_*/
-- app.finance_* table anywhere in this migration (confirmed by direct grep before
-- commit, mirroring PRC-265's own equivalent confirmation for app.finance_*) -- every
-- read below is a plain SELECT, and every metric is either a genuinely new aggregate
-- over already-canonical evidence, or a direct reuse of an existing RPC's own output.
--
-- ===========================================================================
-- Design decisions, disclosed rather than left implicit
-- ===========================================================================
--
-- 1. **Every metric is source-cited, versioned, and gated on an EXISTING PRC
--    permission action** -- `app.procurement_metric_definitions` mirrors
--    `app.vendor_kpi_definitions`' (PRC-264) own root+version-collapsed catalogue
--    shape (`version_no`/`is_current`/`supersedes_definition_id`, at most one current
--    row per `code`), but is Supreme-registered/code-shipped rather than
--    tenant-authored -- these are eleven FIXED, auditable SQL aggregates over
--    canonical evidence, never a tenant-authored formula (the same "fixed calculator,
--    not a free-form expression" posture PRC-264's own design note 1 already
--    established for its KPI catalogue). `required_action`/`additional_mask_action`
--    reuse ONLY the exact PRC actions already seeded by `20260716103445_create_roles_
--    permissions.sql` (`View`, `View cost`) and `20260730580000_*.sql` (`View personal
--    data`, `Export`) -- confirmed by direct grep before writing a single function
--    below; no new permission action is inserted anywhere in this migration. No metric
--    here reads any personal-data-shaped field (vendor CONTACT name/email lives on
--    `app.vendor_contacts`, never read by this migration) -- `PRC:View personal data`
--    is therefore never invoked anywhere in this capability, a disclosed, reasoned
--    absence, not an oversight.
-- 2. **No metric recomputes a duplicate scoring/matching engine.** Rate
--    competitiveness (group 2) reads `app.vendor_kpi_metric_values` where
--    `kpi_code='rate_competitiveness'` verbatim (PRC-264's own market-percentile
--    calculator, unmodified). Performance (group 6) reads `app.vendor_kpi_scorecards`'
--    own already-published `band`/`composite_score` verbatim. Match variance/exception
--    (group 7) is satisfied entirely by REUSING PRC-265's own already-VERIFIED
--    `app.get_vendor_bill_match_reconciliation_status` (batch-4 Tier C hardened,
--    `20260730770000_*.sql`) -- this migration adds ZERO new SQL for group 7, wiring
--    the existing RPC straight into this dashboard's own service/UI layer and citing
--    it in the metric catalogue, never a second, divergent variance number.
-- 3. **Cost-shaped aggregate fields are masked exactly like every sibling PRC-25x/26x
--    RPC** -- `app.has_prc_view_cost` (PRC-252) gates `sum()`/currency-amount columns
--    in the PO summary (group 5), returned as `null` + an explicit `cost_masked`
--    boolean flag, NEVER a zero (`app.get_dashboard_margin_summary`'s (COM-158) own
--    established "null, not zero" convention) -- masked at the SQL layer, inside the
--    aggregate itself (`case when v_can_view_cost then sum(...) else null end`,
--    PRC-265's own `get_vendor_bill_match_reconciliation_status` precedent), never
--    left to a client-side strip that a browser devtools inspection could bypass. No
--    aggregate here groups or orders by a masked field, and no aggregate exposes a
--    rank/percentile/count computed FROM a cost-shaped column to a caller who could
--    not read that column directly -- the one ranking metric this migration adds
--    (competitiveness band, group 2) buckets the KPI's own already-non-cost
--    `normalized_score` (0-100, never a raw currency amount, PRC-264 design note 3),
--    so no inference path exists from a masked amount to a visible rank anywhere in
--    this migration.
-- 4. **Every read RPC takes an explicit `p_tenant_id` and checks `evaluate_permission`
--    as its first statement** -- C-05 discipline, matching every already-hardened
--    PRC-264/265 read RPC exactly; no by-id lookup in this migration discloses
--    existence before the permission check (the four saved-view by-id functions take
--    no `p_tenant_id` parameter, so the row lookup is structurally required first,
--    the same accepted exception PRC-264's own six lookup-by-global-id functions
--    already established -- "not found" and "not this actor's own view" are folded
--    into the identical error message, so a non-owner cannot distinguish the two).
-- 5. **Saved views are the one new user-facing write surface, and idempotency compares
--    the FULL target tuple (C-01), not just the key** -- `app.
--    procurement_dashboard_saved_views` is a strictly OWNER-private object (RLS:
--    `owner_auth_user_id = auth.uid() or is_supreme_admin()`, never tenant-wide), the
--    literal "a user's own named filter/sort configuration" this checkpoint's own spec
--    names -- distinct from `app.vendor_kpi_definitions`' tenant-wide visibility.
-- 6. **The generic Background Job Framework (PLT-132, `app.enqueue_job`) is reused
--    for export, never a second job mechanism** -- searched first per this
--    checkpoint's own mandate (grep for "PLT-131"/"import_export_job"/"durable_job"
--    across `supabase/migrations/`): `app.jobs`/`app.enqueue_job` (PLT-132,
--    `20260719180000_*.sql`) already exists and already carries the exact
--    `report_generation` job type COM-159/FIN-213/OPS-183 (Commercial/Finance/
--    Operations' own "Dashboard and Reports" precedent) all three already reuse
--    verbatim for the identical purpose. `app.report_types`/`app.report_runs`/
--    `app.record_report_run` (COM-159, `20260724330000_*.sql`) are REUSED directly,
--    not duplicated -- this migration inserts ten new `report_types` rows (one per
--    exportable metric; the compliance-expiry QUEUE, item 2 below, is a live work
--    queue, not a bounded export target, and deliberately has no `report_types` row)
--    and adds exactly one new function, `app.enqueue_procurement_report_export`
--    (`PRC:Export`-gated, mirroring `app.enqueue_finance_report_export`/`app.
--    enqueue_ops_report_export`'s identical body shape -- neither of those functions'
--    own migrations may be edited).
-- 7. **A genuine, disclosed, worked-around gap found in the REUSED `app.enqueue_job`
--    (PLT-132) primitive: its own idempotency replay matches the key but never
--    verifies the target tuple (the exact C-01 class this repository's own taxonomy
--    names) -- confirmed by direct code read, not fixed there (PLT-132 is Platform
--    Core, outside this prompt's own allowed-files scope, and `20260719180000_*.sql`
--    is an already-applied migration this task has no mandate to edit).**
--    `app.enqueue_procurement_report_export` therefore performs its OWN full-tuple
--    idempotency check directly against `app.jobs` (real, granted-select, already
--    unique-keyed `(tenant_id, idempotency_key)`) BEFORE ever calling `app.enqueue_job`
--    -- a reused-key replay with a DIFFERENT `report_type_code`/`parameters` is
--    rejected with `idempotency_key_conflict` at this migration's own call site,
--    never silently mismatched inside the shared primitive. `app.jobs` is not extended
--    or altered by this migration in any way. Registered as `ISS-2026-053` in
--    `docs/runtime/KNOWN_ISSUES.md`.
-- 8. **"Schedule" (a recurring/cron-triggered export) is explicitly NOT built.** No
--    scheduler/worker runtime exists anywhere in this repository (`ISS-2026-015`,
--    already carried unmodified by COM-159/FIN-213/OPS-183's own identical disclosure)
--    -- only the bounded, human-triggered async EXPORT half of "export/schedule job
--    records" is implemented. Disclosed here and in the build log, never silently
--    dropped (taxonomy C-23).
-- 9. **No materialized view, replica, or cache is introduced.** Every metric reads
--    live OLTP directly, matching RPD-014's own "no automatic warehouse/materialized
--    architecture" business rule (Prompt 266 section 24) -- every new index below is
--    added only for this migration's own two brand-new tables; every pre-existing
--    table this migration SELECTs from is left untouched, and its own existing
--    indexes (`purchase_orders_tenant_status_idx`, `vendor_contracts_tenant_effective_
--    end_idx`, `vendor_rate_versions_tenant_status_idx`, `vendor_kpi_scorecards_
--    tenant_vendor_idx`, `vendor_assignment_invitations_status_idx`, etc.) already
--    cover this migration's own WHERE/GROUP BY shapes, confirmed by direct `EXPLAIN`
--    against the seeded db-test fixture (see the db-test file's own closing section)
--    -- no speculative index is added anywhere in this migration (RPD-014).
--
-- Per ERR-2026-004: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants, the standing
-- per-migration convention since PLT-118.

-- ===========================================================================
-- 1. app.procurement_metric_definitions -- versioned, code-shipped metric/report
--    definition catalog (design note 1). Mirrors app.report_types' (COM-159)
--    Supreme-registered/idempotent-register shape, extended with the genuine
--    version/supersede chain app.vendor_kpi_definitions (PRC-264) establishes, plus
--    the exact source/formula/grain/freshness/gate columns Prompt 266's own spec
--    names.
-- ===========================================================================

create table app.procurement_metric_definitions (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  metric_group text not null,
  version_no integer not null default 1,
  is_current boolean not null default true,
  supersedes_definition_id uuid references app.procurement_metric_definitions (id),
  name text not null,
  description text,
  source_tables text[] not null,
  source_columns text[] not null,
  formula text not null,
  grain text not null,
  freshness_rule text not null,
  required_action text not null,
  additional_mask_action text,
  source_function text not null,
  status text not null default 'active',
  registered_by text,
  created_at timestamptz not null default now(),
  constraint procurement_metric_definitions_metric_group_check check (metric_group in (
    'vendor_risk_compliance', 'rate_validity_competitiveness', 'rfq_response_cycle',
    'capacity_acceptance', 'po_contract', 'performance', 'match_variance_exception'
  )),
  constraint procurement_metric_definitions_status_check check (status in ('active', 'retired')),
  constraint procurement_metric_definitions_version_check check (version_no > 0),
  constraint procurement_metric_definitions_not_self_supersede check (supersedes_definition_id is null or supersedes_definition_id <> id),
  constraint procurement_metric_definitions_source_tables_check check (array_length(source_tables, 1) >= 1),
  constraint procurement_metric_definitions_source_columns_check check (array_length(source_columns, 1) >= 1),
  constraint procurement_metric_definitions_required_action_check check (required_action in ('View', 'View cost', 'View personal data')),
  constraint procurement_metric_definitions_mask_action_check check (additional_mask_action is null or additional_mask_action in ('View cost', 'View personal data')),
  constraint procurement_metric_definitions_number_version_unique unique (code, version_no)
);

comment on table app.procurement_metric_definitions is
  'PRC-266: one row per metric/report definition VERSION; code is the stable business identity (design note 1). At most one current row per code, enforced by procurement_metric_definitions_current_unique below. Supreme-registered/code-shipped (mirrors app.report_types, COM-159), not tenant-authored -- every formula is a fixed, auditable SQL aggregate, never a tenant expression.';

create unique index procurement_metric_definitions_current_unique on app.procurement_metric_definitions (code) where is_current;
create index procurement_metric_definitions_group_idx on app.procurement_metric_definitions (metric_group, status);

create function app.register_procurement_metric_definition(
  p_code text,
  p_metric_group text,
  p_name text,
  p_description text,
  p_source_tables text[],
  p_source_columns text[],
  p_formula text,
  p_grain text,
  p_freshness_rule text,
  p_required_action text,
  p_additional_mask_action text,
  p_source_function text,
  p_actor_auth_user_id uuid,
  p_registered_by text
)
returns app.procurement_metric_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_current app.procurement_metric_definitions;
  v_exists boolean;
  v_next_version integer;
  v_new app.procurement_metric_definitions;
begin
  -- C-13/ATW-031: is_supreme_admin validates the CLAIMED actor's authority, never that
  -- the calling session IS that actor -- assert identity first, matching the single
  -- choke point app.evaluate_permission already wires this same check into.
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may register a procurement metric definition'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current from app.procurement_metric_definitions where code = p_code and is_current;
  v_exists := found;

  -- Idempotent-if-unchanged, mirroring app.register_report_type's own shape, but
  -- comparing the FULL definition tuple (not merely "code already exists") before
  -- deciding this is truly a no-op re-registration.
  if v_exists
    and v_current.metric_group = p_metric_group
    and v_current.name = p_name
    and v_current.description is not distinct from p_description
    and v_current.source_tables = p_source_tables
    and v_current.source_columns = p_source_columns
    and v_current.formula = p_formula
    and v_current.grain = p_grain
    and v_current.freshness_rule = p_freshness_rule
    and v_current.required_action = p_required_action
    and v_current.additional_mask_action is not distinct from p_additional_mask_action
    and v_current.source_function = p_source_function
  then
    return v_current;
  end if;

  if v_exists then
    update app.procurement_metric_definitions set is_current = false where id = v_current.id;
    v_next_version := v_current.version_no + 1;
  else
    v_next_version := 1;
  end if;

  insert into app.procurement_metric_definitions (
    code, metric_group, version_no, is_current, supersedes_definition_id, name, description,
    source_tables, source_columns, formula, grain, freshness_rule, required_action, additional_mask_action,
    source_function, status, registered_by
  ) values (
    p_code, p_metric_group, v_next_version, true, case when v_exists then v_current.id else null end, p_name, p_description,
    p_source_tables, p_source_columns, p_formula, p_grain, p_freshness_rule, p_required_action, p_additional_mask_action,
    p_source_function, 'active', p_registered_by
  )
  returning * into v_new;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_registered_by, 'register_procurement_metric_definition',
    'app.procurement_metric_definitions', v_new.id, 'success', null,
    case when v_exists then to_jsonb(v_current) else null end, to_jsonb(v_new)
  );

  return v_new;
end;
$$;

comment on function app.register_procurement_metric_definition is
  'PRC-266: Supreme-only. Idempotent-if-unchanged (returns the current row untouched when every field matches); a genuine change to an already-registered code opens a new version and marks the prior one superseded, mirroring app.vendor_kpi_definitions'' own root+version-collapsed shape (PRC-264).';

create function app.retire_procurement_metric_definition(p_code text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.procurement_metric_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_current app.procurement_metric_definitions;
begin
  -- C-13/ATW-031: identity check before authority check (see the register function's
  -- own identical comment immediately above).
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if not app.is_supreme_admin(p_actor_auth_user_id) then
    raise exception 'insufficient_authority: only Supreme Admin may retire a procurement metric definition'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_current from app.procurement_metric_definitions where code = p_code and is_current;
  if not found then
    raise exception 'procurement_metric_definition_not_found: no current definition for code %', p_code using errcode = 'no_data_found';
  end if;

  update app.procurement_metric_definitions set status = 'retired' where id = v_current.id
  returning * into v_current;

  perform app.capture_audit_event(
    null, p_actor_auth_user_id, p_actor_label, 'retire_procurement_metric_definition',
    'app.procurement_metric_definitions', v_current.id, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_current;
end;
$$;

comment on function app.retire_procurement_metric_definition is
  'PRC-266: Supreme-only. Sets status=retired on the current version of code; app.enqueue_procurement_report_export refuses a retired report type via app.report_types'' own identical status check.';

-- ===========================================================================
-- 2. app.procurement_dashboard_saved_views -- a user's OWN named filter/sort
--    configuration (design note 5). Strictly owner-private, never tenant-wide.
-- ===========================================================================

create table app.procurement_dashboard_saved_views (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  owner_auth_user_id uuid not null references auth.users (id),
  metric_group text not null,
  name text not null,
  description text,
  filters jsonb not null default '{}'::jsonb,
  sort jsonb not null default '{}'::jsonb,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint procurement_dashboard_saved_views_metric_group_check check (metric_group in (
    'vendor_risk_compliance', 'rate_validity_competitiveness', 'rfq_response_cycle',
    'capacity_acceptance', 'po_contract', 'performance', 'match_variance_exception'
  )),
  constraint procurement_dashboard_saved_views_name_check check (length(trim(name)) > 0),
  constraint procurement_dashboard_saved_views_filters_check check (jsonb_typeof(filters) = 'object'),
  constraint procurement_dashboard_saved_views_sort_check check (jsonb_typeof(sort) = 'object')
);

comment on table app.procurement_dashboard_saved_views is
  'PRC-266: a user''s own named filter/sort configuration for one dashboard metric_group (Prompt 266 section 20). RLS-scoped to owner_auth_user_id = auth.uid() only (design note 5) -- distinct from every tenant-wide PRC-25x/26x table.';

create index procurement_dashboard_saved_views_owner_idx on app.procurement_dashboard_saved_views (tenant_id, owner_auth_user_id, created_at desc);
create unique index procurement_dashboard_saved_views_idempotency_key_unique on app.procurement_dashboard_saved_views (tenant_id, owner_auth_user_id, idempotency_key) where idempotency_key is not null;

create function app.touch_procurement_dashboard_saved_view_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger procurement_dashboard_saved_views_touch_row
  before update on app.procurement_dashboard_saved_views
  for each row
  execute function app.touch_procurement_dashboard_saved_view_row();

create function app.create_procurement_dashboard_saved_view(
  p_tenant_id uuid,
  p_metric_group text,
  p_name text,
  p_description text,
  p_filters jsonb,
  p_sort jsonb,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.procurement_dashboard_saved_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_sort jsonb := coalesce(p_sort, '{}'::jsonb);
  v_existing app.procurement_dashboard_saved_views;
  v_view app.procurement_dashboard_saved_views;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not (p_metric_group = any (array[
    'vendor_risk_compliance', 'rate_validity_competitiveness', 'rfq_response_cycle',
    'capacity_acceptance', 'po_contract', 'performance', 'match_variance_exception'
  ])) then
    raise exception 'invalid_metric_group: % is not a known dashboard metric group', p_metric_group using errcode = 'check_violation';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a saved view requires a non-empty name' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_filters) then
    raise exception 'saved_view_unsafe_filters: filters failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_sort) then
    raise exception 'saved_view_unsafe_sort: sort failed structural validation' using errcode = 'check_violation';
  end if;

  -- C-01: idempotency replay compares the FULL target tuple, not just the key.
  if p_idempotency_key is not null then
    select * into v_existing
    from app.procurement_dashboard_saved_views
    where tenant_id = p_tenant_id and owner_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.metric_group is distinct from p_metric_group
        or v_existing.name is distinct from p_name
        or v_existing.description is distinct from p_description
        or v_existing.filters is distinct from v_filters
        or v_existing.sort is distinct from v_sort
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different saved view', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- C-02: the insert alone is nested in its own exception scope, so a genuine
  -- concurrent-insert race is recovered here without swallowing the deliberate
  -- idempotency_key_conflict raise above (which lives outside this block).
  begin
    insert into app.procurement_dashboard_saved_views (
      tenant_id, owner_auth_user_id, metric_group, name, description, filters, sort, idempotency_key, created_by
    ) values (
      p_tenant_id, p_actor_auth_user_id, p_metric_group, p_name, p_description, v_filters, v_sort, p_idempotency_key, p_actor_label
    )
    returning * into v_view;
  exception when unique_violation then
    select * into v_existing
    from app.procurement_dashboard_saved_views
    where tenant_id = p_tenant_id and owner_auth_user_id = p_actor_auth_user_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
    raise;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_procurement_dashboard_saved_view',
    'app.procurement_dashboard_saved_views', v_view.id, 'success', null, null, to_jsonb(v_view)
  );

  return v_view;
end;
$$;

create function app.update_procurement_dashboard_saved_view(
  p_view_id uuid,
  p_expected_version integer,
  p_name text,
  p_description text,
  p_filters jsonb,
  p_sort jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.procurement_dashboard_saved_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.procurement_dashboard_saved_views;
  v_decision app.rbac_decision;
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_sort jsonb := coalesce(p_sort, '{}'::jsonb);
  v_updated app.procurement_dashboard_saved_views;
begin
  -- No p_tenant_id parameter -- the row lookup is structurally required before the
  -- permission check can even run (PRC-264's own established, accepted exception to
  -- C-05 for by-id functions with no tenant parameter). "Not found" and "not this
  -- actor's own view" fold into the identical error, never disclosing which.
  select * into v_view from app.procurement_dashboard_saved_views where id = p_view_id for update;
  if not found or v_view.owner_auth_user_id <> p_actor_auth_user_id then
    raise exception 'procurement_dashboard_saved_view_not_found: % is not a known saved view for this actor', p_view_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_view.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_view.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name_required: a saved view requires a non-empty name' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_filters) then
    raise exception 'saved_view_unsafe_filters: filters failed structural validation' using errcode = 'check_violation';
  end if;
  if not app.validate_config_value(v_sort) then
    raise exception 'saved_view_unsafe_sort: sort failed structural validation' using errcode = 'check_violation';
  end if;

  -- C-03: the versioned update is immediately followed by an explicit stale-version guard.
  update app.procurement_dashboard_saved_views
  set name = p_name, description = p_description, filters = v_filters, sort = v_sort
  where id = p_view_id and record_version = p_expected_version
  returning * into v_updated;

  if not found then
    raise exception 'stale_version: saved view % was changed by another request -- reload and retry', p_view_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_view.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_procurement_dashboard_saved_view',
    'app.procurement_dashboard_saved_views', v_view.id, 'success', null, to_jsonb(v_view), to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

create function app.delete_procurement_dashboard_saved_view(
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
  v_view app.procurement_dashboard_saved_views;
  v_decision app.rbac_decision;
  v_deleted_count integer;
begin
  select * into v_view from app.procurement_dashboard_saved_views where id = p_view_id for update;
  if not found or v_view.owner_auth_user_id <> p_actor_auth_user_id then
    raise exception 'procurement_dashboard_saved_view_not_found: % is not a known saved view for this actor', p_view_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_view.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_view.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  delete from app.procurement_dashboard_saved_views where id = p_view_id and record_version = p_expected_version;
  get diagnostics v_deleted_count = row_count;
  if v_deleted_count = 0 then
    raise exception 'stale_version: saved view % was changed by another request -- reload and retry', p_view_id
      using errcode = 'check_violation';
  end if;

  perform app.capture_audit_event(
    v_view.tenant_id, p_actor_auth_user_id, p_actor_label, 'delete_procurement_dashboard_saved_view',
    'app.procurement_dashboard_saved_views', p_view_id, 'success', null, to_jsonb(v_view), null
  );

  return true;
end;
$$;

create function app.get_procurement_dashboard_saved_view(p_view_id uuid, p_actor_auth_user_id uuid)
returns app.procurement_dashboard_saved_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_view app.procurement_dashboard_saved_views;
  v_decision app.rbac_decision;
begin
  select * into v_view from app.procurement_dashboard_saved_views where id = p_view_id;
  if not found or v_view.owner_auth_user_id <> p_actor_auth_user_id then
    raise exception 'procurement_dashboard_saved_view_not_found: % is not a known saved view for this actor', p_view_id
      using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_view.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_view.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_view;
end;
$$;

create function app.list_procurement_dashboard_saved_views(
  p_tenant_id uuid,
  p_metric_group text,
  p_actor_auth_user_id uuid,
  p_limit integer default 25,
  p_cursor timestamptz default null
)
returns setof app.procurement_dashboard_saved_views
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.procurement_dashboard_saved_views
  where tenant_id = p_tenant_id
    and owner_auth_user_id = p_actor_auth_user_id
    and (p_metric_group is null or metric_group = p_metric_group)
    and (p_cursor is null or created_at < p_cursor)
  order by created_at desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

comment on function app.list_procurement_dashboard_saved_views is
  'PRC-266: always scoped to the CALLING actor''s own views only (owner_auth_user_id = p_actor_auth_user_id), never another user''s, even for a tenant_admin -- "a user''s own" (Prompt 266 section 20) is literal. Cursor-paginated on created_at desc, matching app.list_vendor_contracts'' own established shape.';

-- ===========================================================================
-- 3. Group 1 -- Vendor status/risk/compliance-expiry (source: app.vendor_profiles,
--    app.vendor_compliance_status, app.vendor_kpi_scorecards' own already-published
--    band -- never a second risk score).
-- ===========================================================================

create function app.get_procurement_dashboard_vendor_risk_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  lifecycle_status text,
  vendor_count bigint,
  compliance_hold_count bigint,
  band_excellent_count bigint,
  band_good_count bigint,
  band_watch_count bigint,
  band_poor_count bigint
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    vp.lifecycle_status,
    count(distinct vp.master_record_id)::bigint,
    count(distinct vp.master_record_id) filter (where vch.has_hold)::bigint,
    count(distinct vp.master_record_id) filter (where sc.band = 'excellent')::bigint,
    count(distinct vp.master_record_id) filter (where sc.band = 'good')::bigint,
    count(distinct vp.master_record_id) filter (where sc.band = 'watch')::bigint,
    count(distinct vp.master_record_id) filter (where sc.band = 'poor')::bigint
  from app.vendor_profiles vp
  left join lateral (
    select bool_or(vcs.eligibility_hold) as has_hold
    from app.vendor_compliance_status vcs
    where vcs.vendor_master_record_id = vp.master_record_id
  ) vch on true
  left join lateral (
    select k.band
    from app.vendor_kpi_scorecards k
    where k.vendor_master_id = vp.master_record_id and k.is_current and k.status = 'published'
    limit 1
  ) sc on true
  where vp.tenant_id = p_tenant_id
  group by vp.lifecycle_status
  order by vp.lifecycle_status;
end;
$$;

comment on function app.get_procurement_dashboard_vendor_risk_summary is
  'PRC-266: PRC:View. Vendor count by lifecycle_status, with compliance_hold_count and current-published-scorecard band counts folded in via LEFT JOIN LATERAL -- never a second compliance/risk computation (app.vendor_compliance_status.eligibility_hold and app.vendor_kpi_scorecards.band are read verbatim). No cost-shaped or personal-data-shaped column anywhere in this projection.';

create function app.list_procurement_vendor_risk_dashboard_rows(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_lifecycle_status text,
  p_compliance_hold_only boolean,
  p_band text,
  p_search text,
  p_limit integer default 25,
  p_cursor timestamptz default null
)
returns table (
  vendor_master_id uuid,
  legal_name text,
  vendor_category text,
  lifecycle_status text,
  compliance_hold boolean,
  compliance_expiring_soon_count integer,
  compliance_expired_count integer,
  scorecard_band text,
  scorecard_composite_score numeric,
  scorecard_window_end timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_band is not null and not (p_band = any (array['excellent', 'good', 'watch', 'poor'])) then
    raise exception 'invalid_band: % is not a known scorecard band', p_band using errcode = 'check_violation';
  end if;

  return query
  select
    vp.master_record_id,
    vp.legal_name,
    vp.vendor_category,
    vp.lifecycle_status,
    coalesce(vch.has_hold, false),
    coalesce(vch.expiring_soon_count, 0)::integer,
    coalesce(vch.expired_count, 0)::integer,
    sc.band,
    sc.composite_score,
    sc.window_end,
    vp.created_at
  from app.vendor_profiles vp
  left join lateral (
    select
      bool_or(vcs.eligibility_hold) as has_hold,
      count(*) filter (where vcs.status = 'expiring_soon') as expiring_soon_count,
      count(*) filter (where vcs.status = 'expired') as expired_count
    from app.vendor_compliance_status vcs
    where vcs.vendor_master_record_id = vp.master_record_id
  ) vch on true
  left join lateral (
    select k.band, k.composite_score, k.window_end
    from app.vendor_kpi_scorecards k
    where k.vendor_master_id = vp.master_record_id and k.is_current and k.status = 'published'
    limit 1
  ) sc on true
  where vp.tenant_id = p_tenant_id
    and (p_lifecycle_status is null or vp.lifecycle_status = p_lifecycle_status)
    and (p_compliance_hold_only is not true or coalesce(vch.has_hold, false))
    and (p_band is null or sc.band = p_band)
    and (p_search is null or vp.legal_name ilike '%' || p_search || '%' or vp.trade_name ilike '%' || p_search || '%')
    and (p_cursor is null or vp.created_at < p_cursor)
  order by vp.created_at desc
  limit least(coalesce(p_limit, 25), 100);
end;
$$;

comment on function app.list_procurement_vendor_risk_dashboard_rows is
  'PRC-266: cursor-paginated (created_at desc) vendor risk/compliance-expiry work queue -- the dashboard''s main drilldown list, filterable by lifecycle_status/compliance_hold/band and searchable by legal_name/trade_name. Identical field policy to app.list_vendor_profiles/app.get_vendor_kpi_scorecard (no field here is masked by any PRC-264/PRC-251 RPC either, so none is masked here).';

-- ===========================================================================
-- 4. Group 2 -- Rate validity/competitiveness (source: app.vendor_rate_versions'
--    own validity/approval columns, and PRC-264's own already-computed
--    rate_competitiveness KPI -- never a second competitiveness number).
-- ===========================================================================

create function app.get_procurement_dashboard_rate_validity_summary(p_tenant_id uuid, p_actor_auth_user_id uuid, p_as_of timestamptz default now())
returns table (
  currency text,
  validity_bucket text,
  rate_count bigint
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    rv.currency,
    case
      when rv.approval_status <> 'approved' then rv.approval_status
      when rv.effective_to is not null and rv.effective_to <= p_as_of then 'expired'
      when rv.effective_to is not null and rv.effective_to <= p_as_of + interval '30 days' then 'expiring_soon'
      else 'active'
    end as validity_bucket,
    count(*)::bigint
  from app.vendor_rate_versions rv
  where rv.tenant_id = p_tenant_id
  group by rv.currency, validity_bucket
  order by rv.currency, validity_bucket;
end;
$$;

comment on function app.get_procurement_dashboard_rate_validity_summary is
  'PRC-266: PRC:View. Rate-version count by (currency, validity_bucket). Reuses app.vendor_rate_versions.approval_status'' own real vocabulary directly for the non-approved buckets (pending_approval/rejected/withdrawn/superseded), rather than inventing a second status vocabulary. p_as_of defaults to now() -- live OLTP, not cached.';

create function app.get_procurement_dashboard_rate_competitiveness_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (
  competitiveness_band text,
  vendor_count bigint,
  avg_score numeric
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    case
      when mv.normalized_score is null then 'not_computed'
      when mv.normalized_score >= 80 then 'strong'
      when mv.normalized_score >= 50 then 'moderate'
      else 'weak'
    end as competitiveness_band,
    count(*)::bigint,
    round(avg(mv.normalized_score), 2)
  from app.vendor_profiles vp
  left join lateral (
    select v.normalized_score
    from app.vendor_kpi_metric_values v
    where v.vendor_master_id = vp.master_record_id and v.kpi_code = 'rate_competitiveness' and v.is_current
    order by v.window_end desc
    limit 1
  ) mv on true
  where vp.tenant_id = p_tenant_id
  group by competitiveness_band
  order by competitiveness_band;
end;
$$;

comment on function app.get_procurement_dashboard_rate_competitiveness_summary is
  'PRC-266: PRC:View. Buckets PRC-264''s own already-computed rate_competitiveness KPI (app.vendor_kpi_metric_values.normalized_score, is_current, most recent window_end per vendor) into strong/moderate/weak/not_computed -- never recomputes the market-percentile formula itself. normalized_score is a 0-100 score, never a raw currency amount (PRC-264 design note 3), so no PRC:View cost gate applies here.';

-- ===========================================================================
-- 5. Group 3 -- RFQ response rate / cycle time (source: app.rfqs,
--    app.rfq_invitations, app.rfq_responses).
-- ===========================================================================

create function app.get_procurement_dashboard_rfq_cycle_summary(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_window_start timestamptz default null,
  p_window_end timestamptz default null
)
returns table (
  rfq_status text,
  rfq_count bigint,
  invitation_count bigint,
  response_count bigint,
  response_rate_pct numeric,
  avg_cycle_hours numeric
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_window_start is not null and p_window_end is not null and p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  return query
  select
    r.status,
    count(distinct r.id)::bigint,
    count(inv.id)::bigint,
    count(inv.id) filter (where inv.status = 'responded')::bigint,
    case when count(inv.id) = 0 then null else round(100.0 * count(inv.id) filter (where inv.status = 'responded') / count(inv.id), 2) end,
    round(avg(extract(epoch from (resp.received_at - inv.invited_at)) / 3600.0) filter (where resp.received_at is not null), 2)
  from app.rfqs r
  left join app.rfq_invitations inv on inv.rfq_id = r.id
  left join lateral (
    select rr.received_at
    from app.rfq_responses rr
    where rr.rfq_invitation_id = inv.id
    order by rr.version desc
    limit 1
  ) resp on true
  where r.tenant_id = p_tenant_id
    and (p_window_start is null or r.created_at >= p_window_start)
    and (p_window_end is null or r.created_at < p_window_end)
  group by r.status
  order by r.status;
end;
$$;

comment on function app.get_procurement_dashboard_rfq_cycle_summary is
  'PRC-266: PRC:View. Per rfqs.status: invitation/response counts, response_rate_pct, and avg_cycle_hours (invited_at -> the latest rfq_responses.received_at per invitation). p_window_start/p_window_end filter on rfqs.created_at; both default to null (all-time). No cost-shaped column read (rfq_responses.total_amount is deliberately never selected here).';

-- ===========================================================================
-- 6. Group 4 -- Capacity / acceptance (source: app.vendor_capacity_reservations,
--    app.vendor_assignment_invitations' own accept/decline events -- PRC-264's
--    additive responded_at column).
-- ===========================================================================

create function app.get_procurement_dashboard_capacity_reservation_summary(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_window_start timestamptz default null,
  p_window_end timestamptz default null
)
returns table (status text, reservation_count bigint)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select res.status, count(*)::bigint
  from app.vendor_capacity_reservations res
  where res.tenant_id = p_tenant_id
    and (p_window_start is null or res.created_at >= p_window_start)
    and (p_window_end is null or res.created_at < p_window_end)
  group by res.status
  order by res.status;
end;
$$;

comment on function app.get_procurement_dashboard_capacity_reservation_summary is
  'PRC-266: PRC:View. Reservation count by status (held/accepted/declined/consumed/released) -- the accept rate is directly derivable from these counts client-side (non-sensitive arithmetic over already-fetched non-masked counts, never a server-computed masked ratio).';

create function app.get_procurement_dashboard_assignment_acceptance_summary(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_window_start timestamptz default null,
  p_window_end timestamptz default null
)
returns table (status text, invitation_count bigint, avg_response_hours numeric)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    inv.status,
    count(*)::bigint,
    round(avg(extract(epoch from (inv.responded_at - inv.created_at)) / 3600.0) filter (where inv.responded_at is not null), 2)
  from app.vendor_assignment_invitations inv
  where inv.tenant_id = p_tenant_id
    and (p_window_start is null or inv.created_at >= p_window_start)
    and (p_window_end is null or inv.created_at < p_window_end)
  group by inv.status
  order by inv.status;
end;
$$;

comment on function app.get_procurement_dashboard_assignment_acceptance_summary is
  'PRC-266: PRC:View. Invitation count and avg_response_hours (created_at -> PRC-264''s own responded_at, first-write-wins) by status. A row created before PRC-264''s migration has responded_at is null and is correctly excluded from the average, never back-filled or guessed (Prompt 266 section 19).';

-- ===========================================================================
-- 7. Group 5 -- PO / contract (source: app.purchase_orders, app.vendor_contracts).
--    committed_amount is the one cost-shaped field, masked behind PRC:View cost.
-- ===========================================================================

create function app.get_procurement_dashboard_po_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (status text, currency text, po_count bigint, committed_amount numeric, cost_masked boolean)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_can_view_cost boolean;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_can_view_cost := app.has_prc_view_cost(p_tenant_id, p_actor_auth_user_id);

  return query
  select
    po.status,
    po.currency,
    count(*)::bigint,
    case when v_can_view_cost then sum(po.total_amount) else null end,
    not v_can_view_cost
  from app.purchase_orders po
  where po.tenant_id = p_tenant_id
  group by po.status, po.currency
  order by po.status, po.currency;
end;
$$;

comment on function app.get_procurement_dashboard_po_summary is
  'PRC-266: PRC:View, committed_amount additionally gated on PRC:View cost -- masked to null (never zero) with cost_masked=true, matching app.get_vendor_bill_match_reconciliation_status'' (PRC-265) own established "case when v_can_view_cost then sum(...) else null end" shape exactly. po_count is never masked.';

create function app.get_procurement_dashboard_contract_summary(p_tenant_id uuid, p_actor_auth_user_id uuid, p_as_of timestamptz default now())
returns table (status text, contract_count bigint, expiring_soon_count bigint)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    c.status,
    count(*)::bigint,
    count(*) filter (
      where c.status = 'active' and c.effective_end is not null
        and c.effective_end between p_as_of::date and (p_as_of::date + 30)
    )::bigint
  from app.vendor_contracts c
  where c.tenant_id = p_tenant_id
  group by c.status
  order by c.status;
end;
$$;

comment on function app.get_procurement_dashboard_contract_summary is
  'PRC-266: PRC:View. Contract-version count by status, plus expiring_soon_count (active, effective_end within 30 days of p_as_of). app.vendor_contracts carries no header amount column at all (PRC-261''s own disclosed shape) -- there is genuinely no cost-shaped field to mask here.';

-- ===========================================================================
-- 8. Group 6 -- Performance (source: app.vendor_kpi_scorecards' own already-
--    published band/composite_score -- never a second scoring engine).
-- ===========================================================================

create function app.get_procurement_dashboard_performance_summary(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns table (band text, vendor_count bigint, avg_composite_score numeric)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    coalesce(k.band, 'not_banded'),
    count(*)::bigint,
    round(avg(k.composite_score), 2)
  from app.vendor_kpi_scorecards k
  where k.tenant_id = p_tenant_id and k.is_current and k.status = 'published'
  group by coalesce(k.band, 'not_banded')
  order by 1;
end;
$$;

comment on function app.get_procurement_dashboard_performance_summary is
  'PRC-266: PRC:View. Vendor count and avg composite_score by band, over the CURRENT published app.vendor_kpi_scorecards row per vendor only (PRC-264) -- surfaces the existing scorecard verbatim, never a duplicate scoring engine. A vendor with no published scorecard is absent from this metric entirely (already reflected in group 1''s own vendor_count minus its four band columns).';

-- ===========================================================================
-- 9. Group 7 -- Match variance / exception rate. Satisfied ENTIRELY by reusing
--    PRC-265's own already-VERIFIED, batch-4-Tier-C-hardened
--    app.get_vendor_bill_match_reconciliation_status (20260730750000_*.sql,
--    hardened by 20260730770000_*.sql) -- design note 2. Zero new SQL for this
--    group; it is wired into this dashboard's own service/UI layer and cited in
--    the metric catalogue below, never re-implemented.
-- ===========================================================================

-- ===========================================================================
-- 10. Export -- reuses app.report_types/app.report_runs/app.enqueue_job (design
--     note 6). Ten new report_types rows, one per exportable metric (the
--     compliance-expiry QUEUE has none -- design note 6).
-- ===========================================================================

insert into app.report_types (code, name, description, source_function, registered_by) values
  ('vendor_lifecycle_risk_mix', 'Vendor Lifecycle / Risk Mix', 'Vendor count by lifecycle status, with compliance-hold and current scorecard band counts.', 'get_procurement_dashboard_vendor_risk_summary', 'system'),
  ('vendor_rate_validity_mix', 'Vendor Rate Validity Mix', 'Rate-version count by currency and validity bucket (active/expiring_soon/expired/not-yet-approved).', 'get_procurement_dashboard_rate_validity_summary', 'system'),
  ('vendor_rate_competitiveness_band_mix', 'Vendor Rate Competitiveness Band Mix', 'Vendor count and average score bucketed from the existing rate_competitiveness KPI.', 'get_procurement_dashboard_rate_competitiveness_summary', 'system'),
  ('rfq_response_cycle_time', 'RFQ Response Rate / Cycle Time', 'Invitation/response counts, response rate, and average cycle time by RFQ status.', 'get_procurement_dashboard_rfq_cycle_summary', 'system'),
  ('vendor_capacity_reservation_mix', 'Vendor Capacity Reservation Mix', 'Capacity reservation count by status.', 'get_procurement_dashboard_capacity_reservation_summary', 'system'),
  ('vendor_assignment_invitation_acceptance', 'Vendor Assignment Invitation Acceptance', 'Assignment invitation count and average response time by status.', 'get_procurement_dashboard_assignment_acceptance_summary', 'system'),
  ('purchase_order_pipeline_mix', 'Purchase Order Pipeline Mix', 'Purchase order count and committed amount (cost-masked) by status and currency.', 'get_procurement_dashboard_po_summary', 'system'),
  ('vendor_contract_lifecycle_mix', 'Vendor Contract Lifecycle Mix', 'Contract-version count by status, with a 30-day expiring-soon count.', 'get_procurement_dashboard_contract_summary', 'system'),
  ('vendor_performance_scorecard_mix', 'Vendor Performance Scorecard Mix', 'Vendor count and average composite score by current published scorecard band.', 'get_procurement_dashboard_performance_summary', 'system'),
  ('vendor_bill_match_variance_exception_rate', 'Vendor Bill Match Variance / Exception Rate', 'Match-case count and cost-masked total variance by overall status and readiness status (PRC-265).', 'get_vendor_bill_match_reconciliation_status', 'system');

create function app.enqueue_procurement_report_export(
  p_tenant_id uuid,
  p_report_type_code text,
  p_parameters jsonb,
  p_idempotency_key text,
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
  v_parameters jsonb := coalesce(p_parameters, '{}'::jsonb);
  v_existing_job app.jobs;
  v_existing_run app.report_runs;
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

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Export');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Export (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Only this migration's own registered procurement report codes may be exported
  -- through this entry point, even though app.report_types is a shared cross-module
  -- catalogue -- mirrors app.enqueue_finance_report_export/app.enqueue_ops_report_
  -- export's own identical module-scoping discipline.
  if not exists (select 1 from app.procurement_metric_definitions where source_function = v_type.source_function and is_current) then
    raise exception 'report_type_not_procurement_owned: % is not a Procurement dashboard report', p_report_type_code
      using errcode = 'check_violation';
  end if;

  if not app.validate_config_value(v_parameters) then
    raise exception 'report_unsafe_parameters: parameters failed structural validation'
      using errcode = 'check_violation';
  end if;

  -- Design note 7: app.enqueue_job's (PLT-132) own idempotency replay matches the key
  -- but never verifies the target tuple (a real, confirmed C-01 gap in that ALREADY-
  -- APPLIED, out-of-scope migration -- disclosed as ISS-2026-053, not fixed there).
  -- This function performs its OWN full-tuple idempotency check directly against
  -- app.jobs (already unique-keyed on (tenant_id, idempotency_key)) before ever
  -- calling app.enqueue_job, so a reused key with a DIFFERENT report_type_code/
  -- parameters is rejected here, never silently mismatched inside the shared
  -- primitive.
  if p_idempotency_key is not null then
    select * into v_existing_job from app.jobs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing_job.job_type is distinct from 'report_generation'
        or (v_existing_job.payload ->> 'report_type_code') is distinct from p_report_type_code
        or (v_existing_job.payload -> 'parameters') is distinct from v_parameters
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different export request', p_idempotency_key
          using errcode = 'unique_violation';
      end if;
      select * into v_existing_run from app.report_runs where job_id = v_existing_job.job_id;
      if found then
        return v_existing_run;
      end if;
    end if;
  end if;

  v_job := app.enqueue_job(
    p_tenant_id, 'report_generation',
    jsonb_build_object('report_type_code', p_report_type_code, 'parameters', v_parameters),
    0, p_idempotency_key, 3, p_actor_auth_user_id, p_actor_label
  );

  insert into app.report_runs (
    tenant_id, report_type_code, run_type, status, parameters, job_id,
    requested_by_auth_user_id, created_by
  ) values (
    p_tenant_id, p_report_type_code, 'export', 'queued', v_parameters, v_job.job_id,
    p_actor_auth_user_id, p_actor_label
  )
  returning * into v_run;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enqueue_procurement_report_export',
    'app.report_runs', v_run.id, 'success', null, null,
    jsonb_build_object('report_type_code', p_report_type_code, 'job_id', v_job.job_id)
  );

  return v_run;
end;
$$;

comment on function app.enqueue_procurement_report_export is
  'PRC-266: PRC:Export-gated (Prompt 266 section 26). A parallel entry point to app.enqueue_report_export/app.enqueue_finance_report_export/app.enqueue_ops_report_export -- identical body shape, distinct module-code RBAC check and its own real, full-tuple idempotency check (design note 7). Enqueues a real report_generation job via PLT-132''s own app.enqueue_job (never a bespoke queue) and records the linking app.report_runs row (the same shared table COM-159 already created) at status=queued. No live worker advances it further in this environment -- the same disclosed NOT_RUN condition COM-159/FIN-213/OPS-183 already carry, unchanged by this checkpoint. "Schedule" (recurring export) is explicitly not built (design note 8, ISS-2026-015).';

-- ===========================================================================
-- 11. Metric definition catalogue seed -- eleven rows, one per metric, across all
--     seven required groups (design note 1). Seeded via a direct INSERT, exactly
--     mirroring app.report_types' own seed shape (COM-159) -- NOT routed through
--     app.register_procurement_metric_definition, which is Supreme-Admin-gated and
--     would therefore silently insert ZERO rows at fresh-migration-apply time (no
--     Supreme Admin identity exists yet in a brand-new database) -- a real bug this
--     checkpoint's own db-test iteration caught live (expected 11 current definitions,
--     found 0) before fixing it here. The register/retire functions remain real,
--     tested, callable maintenance paths for any FUTURE catalogue change; they were
--     never the right mechanism for this migration's own bootstrap seed.
-- ===========================================================================

insert into app.procurement_metric_definitions (
  code, metric_group, name, description, source_tables, source_columns, formula, grain, freshness_rule,
  required_action, additional_mask_action, source_function, registered_by
) values
  (
    'vendor_lifecycle_risk_mix', 'vendor_risk_compliance', 'Vendor Lifecycle / Risk Mix',
    'Vendor count by lifecycle status, with compliance-hold and current scorecard band counts.',
    array['app.vendor_profiles', 'app.vendor_compliance_status', 'app.vendor_kpi_scorecards'],
    array['lifecycle_status', 'eligibility_hold', 'band'],
    'count(vendor) grouped by lifecycle_status; compliance_hold_count = count where any compliance_status row has eligibility_hold; band_*_count = count where the current published scorecard''s own band matches',
    'per vendor lifecycle_status, tenant-wide snapshot', 'live OLTP as-of query time (no cache, no batch lag)',
    'View', null, 'get_procurement_dashboard_vendor_risk_summary', 'system'
  ),
  (
    'vendor_compliance_expiry_queue', 'vendor_risk_compliance', 'Vendor Compliance Expiry Queue',
    'Per-vendor drilldown row: lifecycle status, compliance hold/expiry counts, current scorecard band/score.',
    array['app.vendor_profiles', 'app.vendor_compliance_status', 'app.vendor_kpi_scorecards'],
    array['legal_name', 'lifecycle_status', 'eligibility_hold', 'status', 'band', 'composite_score'],
    'one row per vendor; compliance_expiring_soon_count/compliance_expired_count = count of that vendor''s own compliance_status rows at status=expiring_soon/expired',
    'per vendor, tenant-wide, cursor-paginated', 'live OLTP as-of query time (no cache, no batch lag)',
    'View', null, 'list_procurement_vendor_risk_dashboard_rows', 'system'
  ),
  (
    'vendor_rate_validity_mix', 'rate_validity_competitiveness', 'Vendor Rate Validity Mix',
    'Rate-version count by currency and validity bucket.',
    array['app.vendor_rate_versions'], array['currency', 'approval_status', 'effective_to'],
    'count(rate_version) grouped by (currency, case over approval_status/effective_to vs as-of)',
    'per currency per validity bucket, tenant-wide snapshot', 'live OLTP as-of query time (p_as_of parameter, defaults to now())',
    'View', null, 'get_procurement_dashboard_rate_validity_summary', 'system'
  ),
  (
    'vendor_rate_competitiveness_band_mix', 'rate_validity_competitiveness', 'Vendor Rate Competitiveness Band Mix',
    'Vendor count and average score bucketed from the existing rate_competitiveness KPI -- never recomputed here.',
    array['app.vendor_kpi_metric_values'], array['normalized_score', 'kpi_code', 'is_current', 'window_end'],
    'bucket(avg(normalized_score)) where kpi_code=rate_competitiveness and is_current, most recent window_end per vendor -- formula owned by PRC-264''s own market-percentile calculator, not recomputed here',
    'per vendor, most recent current measurement window', 'as-of the vendor''s own most recently calculated rate_competitiveness KPI value, not live-recomputed',
    'View', null, 'get_procurement_dashboard_rate_competitiveness_summary', 'system'
  ),
  (
    'rfq_response_cycle_time', 'rfq_response_cycle', 'RFQ Response Rate / Cycle Time',
    'Invitation/response counts, response rate, and average cycle time by RFQ status.',
    array['app.rfqs', 'app.rfq_invitations', 'app.rfq_responses'],
    array['status', 'invited_at', 'received_at'],
    'response_rate_pct = 100 * count(invitation where status=responded) / count(invitation); avg_cycle_hours = avg(received_at - invited_at) in hours over responded invitations',
    'per rfq status, tenant-wide, optional [window_start, window_end) on rfqs.created_at', 'live OLTP as-of query time (no cache, no batch lag)',
    'View', null, 'get_procurement_dashboard_rfq_cycle_summary', 'system'
  ),
  (
    'vendor_capacity_reservation_mix', 'capacity_acceptance', 'Vendor Capacity Reservation Mix',
    'Capacity reservation count by status.',
    array['app.vendor_capacity_reservations'], array['status', 'created_at'],
    'count(reservation) grouped by status',
    'per reservation status, tenant-wide, optional [window_start, window_end) on created_at', 'live OLTP as-of query time (no cache, no batch lag)',
    'View', null, 'get_procurement_dashboard_capacity_reservation_summary', 'system'
  ),
  (
    'vendor_assignment_invitation_acceptance', 'capacity_acceptance', 'Vendor Assignment Invitation Acceptance',
    'Assignment invitation count and average response time by status.',
    array['app.vendor_assignment_invitations'], array['status', 'created_at', 'responded_at'],
    'avg_response_hours = avg(responded_at - created_at) in hours, PRC-264''s own additive responded_at column, first-write-wins',
    'per invitation status, tenant-wide, optional [window_start, window_end) on created_at', 'live OLTP as-of query time (no cache, no batch lag)',
    'View', null, 'get_procurement_dashboard_assignment_acceptance_summary', 'system'
  ),
  (
    'purchase_order_pipeline_mix', 'po_contract', 'Purchase Order Pipeline Mix',
    'Purchase order count and committed amount (cost-masked) by status and currency.',
    array['app.purchase_orders'], array['status', 'currency', 'total_amount'],
    'count(po) and sum(total_amount) grouped by (status, currency); total_amount masked to null unless the caller holds PRC:View cost',
    'per (status, currency), tenant-wide snapshot', 'live OLTP as-of query time (no cache, no batch lag)',
    'View', 'View cost', 'get_procurement_dashboard_po_summary', 'system'
  ),
  (
    'vendor_contract_lifecycle_mix', 'po_contract', 'Vendor Contract Lifecycle Mix',
    'Contract-version count by status, with a 30-day expiring-soon count.',
    array['app.vendor_contracts'], array['status', 'effective_end'],
    'count(contract) grouped by status; expiring_soon_count = count where status=active and effective_end within 30 days of as-of',
    'per contract status, tenant-wide snapshot', 'live OLTP as-of query time (p_as_of parameter, defaults to now())',
    'View', null, 'get_procurement_dashboard_contract_summary', 'system'
  ),
  (
    'vendor_performance_scorecard_mix', 'performance', 'Vendor Performance Scorecard Mix',
    'Vendor count and average composite score by current published scorecard band -- never a second scoring engine.',
    array['app.vendor_kpi_scorecards'], array['band', 'composite_score', 'is_current', 'status'],
    'count(vendor) and avg(composite_score) grouped by band, over is_current=true and status=published rows only -- owned by PRC-264''s own scorecard publish RPC, not recomputed here',
    'per vendor, current published scorecard only', 'as-of the vendor''s own most recently published scorecard, not live-recomputed',
    'View', null, 'get_procurement_dashboard_performance_summary', 'system'
  ),
  (
    'vendor_bill_match_variance_exception_rate', 'match_variance_exception', 'Vendor Bill Match Variance / Exception Rate',
    'Match-case count and cost-masked total variance by overall status and readiness status -- entirely reuses PRC-265''s own existing RPC.',
    array['app.vendor_bill_match_cases'], array['overall_status', 'readiness_status', 'total_variance_amount', 'evaluated_at'],
    'count(case) and sum(total_variance_amount) grouped by (overall_status, readiness_status); total_variance_amount masked to null unless the caller holds PRC:View cost -- owned entirely by app.get_vendor_bill_match_reconciliation_status (PRC-265), zero new SQL added by this migration',
    'per (overall_status, readiness_status), current match-case versions only (is_current)', 'as-of each match case''s own evaluated_at, not live-recomputed',
    'View', 'View cost', 'get_vendor_bill_match_reconciliation_status', 'system'
  );

-- ===========================================================================
-- 12. RLS + grants.
-- ===========================================================================

alter table app.procurement_dashboard_saved_views enable row level security;

create policy procurement_dashboard_saved_views_select_own on app.procurement_dashboard_saved_views
  for select to authenticated
  using (owner_auth_user_id = auth.uid() or app.is_supreme_admin());

revoke execute on all functions in schema app from public;

grant select on app.procurement_metric_definitions to authenticated, service_role;
grant insert, update on app.procurement_metric_definitions to service_role;

grant select on app.procurement_dashboard_saved_views to authenticated, service_role;
grant insert, update, delete on app.procurement_dashboard_saved_views to service_role;

grant execute on function app.register_procurement_metric_definition(text, text, text, text, text[], text[], text, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.retire_procurement_metric_definition(text, uuid, text) to authenticated, service_role;

grant execute on function app.create_procurement_dashboard_saved_view(uuid, text, text, text, jsonb, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_procurement_dashboard_saved_view(uuid, integer, text, text, jsonb, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.delete_procurement_dashboard_saved_view(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_saved_view(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_procurement_dashboard_saved_views(uuid, text, uuid, integer, timestamptz) to authenticated, service_role;

grant execute on function app.get_procurement_dashboard_vendor_risk_summary(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_procurement_vendor_risk_dashboard_rows(uuid, uuid, text, boolean, text, text, integer, timestamptz) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_rate_validity_summary(uuid, uuid, timestamptz) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_rate_competitiveness_summary(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_rfq_cycle_summary(uuid, uuid, timestamptz, timestamptz) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_capacity_reservation_summary(uuid, uuid, timestamptz, timestamptz) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_assignment_acceptance_summary(uuid, uuid, timestamptz, timestamptz) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_po_summary(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_contract_summary(uuid, uuid, timestamptz) to authenticated, service_role;
grant execute on function app.get_procurement_dashboard_performance_summary(uuid, uuid) to authenticated, service_role;

grant execute on function app.enqueue_procurement_report_export(uuid, text, jsonb, text, uuid, text) to authenticated, service_role;
