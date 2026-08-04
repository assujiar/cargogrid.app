-- Advanced TMS/WMS capability ATW-020 (CG-S10-ATW-020, Prompt 239, "Cycle Count and
-- Inventory Adjustment" -- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md
-- §1). Implements this prompt's own §4 objective: "auditable cycle counting that
-- resolves approved variances through exact ledger movements without directly
-- patching balances."
--
-- Direct upstream: ATW-015 (Inventory Ledger -- app.inventory_balances/app.
-- inventory_movements/app.post_inventory_movement, composed, never re-implemented or
-- directly written), ATW-016 (Lot/Batch/Serial/Expiry -- app.actor_can_view_owner_
-- scoped_row/app.resolve_actor_owner_account_scope, reused directly), ATW-011A (item/
-- UOM identity -- app.item_masters.base_uom_code/app.convert_uom_quantity), ATW-230
-- (app.warehouse_locations), ATW-229 (app.warehouses/app.warehouse_zones/app.
-- lead_record_scope_org_unit_ids), ATW-017 (WMS Picking -- the closest structural
-- precedent for this migration's own "generate a snapshot, claim it, scan-confirm it,
-- resolve it forward" task lifecycle shape, and the direct source of app.wms_pick_
-- record_scope_ok, reused verbatim below rather than re-implemented, per this task's
-- own brief).
--
-- Design boundary (disclosed):
--
-- 1. **Thresholds are fixed to a plan's own row at creation time, never a separate
--    versioned config table.** Prompt 239 §24 names "variance/recount/approval
--    thresholds are explicit and versioned" -- read here as "fixed to this plan's own
--    row, immutable once set, never silently changed after the fact," not as a mandate
--    for a second, independently-versioned threshold-policy table. `ATW-016`'s own
--    `app.item_control_policy_versions` already built exactly that richer,
--    independently-versioned-policy shape for a different (item/owner control) concern;
--    duplicating that machinery here for a single per-plan numeric pair would be new-
--    feature authoring beyond this bounded checkpoint's own scope. No `update_cycle_
--    count_plan_thresholds` RPC exists -- `app.create_cycle_count_plan` is the only
--    place `variance_threshold_pct`/`recount_threshold_pct`/`requires_separate_
--    approver` are ever set, and every one of this migration's own mutation RPCs
--    reads them live off the plan row that RPC's own scope item traces back to,
--    never a second, independently-drifting copy. `variance_threshold_pct` is the
--    plan's own configured materiality tolerance: `app.record_cycle_count_observation`
--    resolves a nonzero variance at or below it directly to `no_variance_closed`
--    (identically to an exact-zero variance -- no manual review, no ledger adjustment
--    posted), checked ahead of the `recount_threshold_pct` escalation.
-- 2. **`app.wms_pick_record_scope_ok` is reused directly, not re-implemented.** It is
--    already generic (its own comment says so) despite its picking-specific name --
--    resolves a warehouse's tenant_id/company_org_unit_id under `SECURITY DEFINER`
--    (bypassing `app.warehouses`' own RLS, which always denies a customer_user actor
--    since it always passes a null `p_customer_account_ref`) and evaluates `app.
--    can_access_record` against it, the identical need this migration's own owner-
--    scoped tables (`app.cycle_count_scope_items`/`app.cycle_count_observations`) have.
--    `app.cycle_count_plans` itself carries no `owner_account_id` (a plan is a
--    warehouse-level operational record, not owned by one customer), so its own RLS
--    mirrors `app.warehouse_zones`' own plain warehouse-join shape instead (design
--    note 5 below).
-- 3. **The "reservation/activity conflict" prevention Prompt 239 §13 requires is a
--    real, DB-enforced partial unique index, not an app-level check alone**: `create
--    unique index cycle_count_scope_items_active_balance_unique on app.cycle_count_
--    scope_items (snapshot_balance_id) where status not in ('adjusted',
--    'no_variance_closed', 'cancelled')` guarantees at most one in-flight cycle-count
--    scope item per inventory balance dimension, across every plan in the tenant, at
--    any time -- structurally, not by convention. `app.freeze_cycle_count_scope`
--    additionally checks this explicitly before inserting (a friendlier
--    `balance_already_in_active_count` error than a raw unique-violation), but the
--    index is the real backstop a concurrent freeze cannot get around: `app.freeze_
--    cycle_count_scope` locks each matching `app.inventory_balances` row `FOR UPDATE`
--    as it scans (a real Postgres row lock, not a table-wide lock), so two concurrent
--    freezes targeting an overlapping balance set serialize on that shared row --
--    the second call's own scan blocks until the first's transaction commits or rolls
--    back, then re-observes the first's own newly-committed scope item and cleanly
--    rejects with `balance_already_in_active_count` rather than racing the unique
--    index to a raw constraint violation. Proven live with two real, separate psql
--    client processes in scripts/db-tests/advanced-tms-cycle-count-adjustment.sql,
--    reusing scripts/db-tests/wms-picking-concurrency-helper.sh verbatim (already
--    fully generic -- takes the two race statements and output paths as environment
--    variables, no picking-specific logic in it at all).
-- 4. **A cycle count never reserves stock.** Unlike `ATW-017`'s own pick tasks, a
--    scope item's own `snapshot_balance_id`/`snapshot_expected_quantity`/`snapshot_
--    record_version` are a real, point-in-time READ snapshot of an `app.inventory_
--    balances` row -- not a commitment against it (no `app.reserve_inventory` call
--    anywhere in this migration). The snapshot's own staleness is instead detected at
--    APPROVAL time: `app.approve_cycle_count_variance` re-locks the CURRENT balance row
--    by `snapshot_balance_id` and compares its live `record_version` against the
--    snapshot's own captured `snapshot_record_version` -- if a real movement posted
--    against that balance between freeze and approval, the live `record_version` will
--    have advanced, and approval is rejected `balance_changed_since_snapshot` rather
--    than posting a now-incorrect adjustment atop stock the ledger has already moved.
-- 5. **`app.cycle_count_plans`' own SELECT RLS mirrors `app.warehouse_zones`' own
--    plain warehouse-join shape** (`app.can_access_record(..., null)`, no owner
--    dimension) -- a plan itself is never customer-owned. `app.cycle_count_scope_
--    items`/`app.cycle_count_observations` reuse the owner-scoped shape `app.
--    wms_pick_tasks`' own policy already established verbatim (design note 2).
-- 6. **Blind-count redaction is server-side and non-negotiable -- no caller-supplied
--    parameter can defeat it.** Every RPC that returns a scope item row -- read
--    (`app.get_cycle_count_scope_item`/`app.list_cycle_count_scope_items`) AND
--    mutation (`app.freeze_cycle_count_scope`/`app.assign_cycle_count_scope_item`/
--    `app.record_cycle_count_observation`, including both of the latter's own
--    idempotent-replay short-circuits) -- computes `v_can_see_expected := (app.
--    evaluate_permission(p_actor_auth_user_id, tenant_id, 'OPS', 'Override')).allowed`
--    itself, from the authenticated actor's own real RBAC grants -- there is no
--    `p_blind`/`p_reveal_expected` parameter anywhere in this migration's own function
--    signatures. A plain counter (OPS:Edit only, never Override) always receives
--    `snapshot_expected_quantity`/`variance_quantity`/`variance_pct`/`snapshot_record_
--    version` as `null` in the returned row -- whether they are reading the item,
--    self-assigning it, self-freezing the scope, or submitting their own blind count --
--    a supervisor (OPS:Override) always sees the real values.
-- 7. **`app.reject_cycle_count_variance` never sets `reviewed_by_auth_user_id`/
--    `reviewed_at`/`review_reason`** -- those columns are reserved, by `app.cycle_
--    count_scope_items_adjusted_requires_review_check`, for a real `adjusted`
--    resolution only. A reject sends the item back to `recount_required` for a fresh
--    count; it is not itself the reviewed outcome those columns record. Who rejected
--    and why is captured in the audit trail (`app.capture_audit_event`'s own `p_
--    reason` argument), not on the row.
-- 8. **A supervisor approving a variance must hold both `OPS:Override` (to approve)
--    and `OPS:Create`** -- the latter because `app.approve_cycle_count_variance`
--    composes `app.post_inventory_movement` (`ATW-015`), which independently gates on
--    `OPS:Create` for the posting actor. This mirrors the identical, already-
--    established composition requirement `ATW-017`'s own `app.confirm_wms_pick_task`
--    (`OPS:Edit`-gated, also composing `app.post_inventory_movement`) already carries
--    -- every fixture role in this migration's own db-test that approves a variance
--    holds `OPS Create/Edit/View/Override` together, the identical "supervisor" role
--    shape `ATW-019`'s own fixture already established.
-- 9. **A location with no `app.inventory_balances` row at all is out of scope for a
--    checkpoint, by design** -- `app.freeze_cycle_count_scope` snapshots only existing
--    balance rows (`status = 'on_hand'`, including a possibly-zero `on_hand` row if one
--    already exists). A location the ledger has never touched (never received,
--    putaway, or moved anything) cannot be cycle-counted through this capability; this
--    is a deliberate, disclosed boundary (a genuinely empty freeze -- zero matching
--    balances -- is a valid, non-error outcome, never fabricated to force a result).
-- 10. **No UI this checkpoint** -- matches every one of ATW-012 through ATW-019's own
--     disclosed boundary ("Scan-first PWA ... UI -- deferred"). No `app/` route, no
--     REST/GraphQL surface; this migration and its TypeScript service layer are the
--     complete deliverable, backend-correctness-first, within this task's own bounded
--     file/migration budget.
-- 11. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 0. Additive widening of app.inventory_movements' own source_type CHECK (never
-- editing the already-applied ATW-015 migration file itself) -- adds 'cycle_count',
-- the identical DROP/ADD CONSTRAINT technique ATW-017 already used to add
-- 'wms_outbound_order'.
alter table app.inventory_movements drop constraint inventory_movements_source_type_check;
alter table app.inventory_movements add constraint inventory_movements_source_type_check check (
  source_type in ('wms_inbound_order', 'wms_outbound_order', 'reservation', 'manual', 'opening_balance', 'reversal', 'cycle_count')
);

-- 1. Plan numbering (identical idiom to app.next_wms_pick_wave_number, ATW-017).
create table app.cycle_count_plan_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

create function app.next_cycle_count_plan_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.cycle_count_plan_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.cycle_count_plan_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'CC-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

comment on function app.next_cycle_count_plan_number is
  'ATW-020: tenant-scoped monotonic plan-number generator, CC-YYYY-NNNNNN, identical idiom to app.next_wms_pick_wave_number (ATW-017). service_role-only -- an internal counter helper, never called directly by a client.';

-- 2. Plan header (design note 1: thresholds fixed at creation, immutable thereafter).
create table app.cycle_count_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  plan_number text not null,
  method text not null default 'full',
  variance_threshold_pct numeric not null default 0,
  recount_threshold_pct numeric not null default 0,
  requires_separate_approver boolean not null default true,
  status text not null default 'draft',
  scope_filter_zone_id uuid references app.warehouse_zones (id),
  scope_filter_location_id uuid references app.warehouse_locations (id),
  scope_filter_item_master_id uuid references app.item_masters (id),
  scope_filter_owner_account_id uuid references app.accounts (id),
  frozen_at timestamptz,
  closed_at timestamptz,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cycle_count_plans_method_check check (method in ('full', 'abc', 'spot')),
  constraint cycle_count_plans_variance_threshold_check check (variance_threshold_pct >= 0),
  constraint cycle_count_plans_recount_threshold_check check (recount_threshold_pct >= 0),
  constraint cycle_count_plans_status_check check (status in ('draft', 'active', 'closed', 'cancelled')),
  constraint cycle_count_plans_plan_number_unique unique (tenant_id, plan_number),
  constraint cycle_count_plans_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.cycle_count_plans is
  'ATW-020: the count plan header. variance_threshold_pct/recount_threshold_pct/requires_separate_approver are set once at app.create_cycle_count_plan and never mutated by any RPC in this migration (design note 1) -- immutable, fixed to this plan''s own row, not a second versioned-config table. No owner_account_id -- a plan is a warehouse-level operational record (design note 5), never customer-owned; scope_filter_owner_account_id merely narrows WHICH balances app.freeze_cycle_count_scope snapshots.';

create index cycle_count_plans_tenant_warehouse_status_idx on app.cycle_count_plans (tenant_id, warehouse_id, status);

create function app.touch_cycle_count_plans_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger cycle_count_plans_touch_row
  before update on app.cycle_count_plans
  for each row
  execute function app.touch_cycle_count_plans_row();

-- 3. Scope items -- the frozen snapshot + per-item lifecycle (design notes 3/4/6).
create table app.cycle_count_scope_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  plan_id uuid not null references app.cycle_count_plans (id),
  warehouse_id uuid not null references app.warehouses (id),
  owner_account_id uuid not null references app.accounts (id),
  item_master_id uuid not null references app.item_masters (id),
  location_id uuid not null references app.warehouse_locations (id),
  lot_number text,
  serial_number text,
  uom_code text not null references app.uoms (code),
  snapshot_balance_id uuid not null references app.inventory_balances (id),
  snapshot_expected_quantity numeric not null,
  snapshot_record_version integer not null,
  snapshot_taken_at timestamptz not null default now(),
  status text not null default 'pending',
  assigned_to_auth_user_id uuid references auth.users (id),
  assigned_to_label text,
  assigned_at timestamptz,
  count_attempt_number integer not null default 0,
  last_observed_quantity numeric,
  variance_quantity numeric,
  variance_pct numeric,
  reviewed_by_auth_user_id uuid references auth.users (id),
  reviewed_by_label text,
  reviewed_at timestamptz,
  review_reason text,
  adjustment_movement_id uuid references app.inventory_movements (id),
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cycle_count_scope_items_expected_quantity_check check (snapshot_expected_quantity >= 0),
  constraint cycle_count_scope_items_count_attempt_check check (count_attempt_number >= 0),
  constraint cycle_count_scope_items_last_observed_check check (last_observed_quantity is null or last_observed_quantity >= 0),
  constraint cycle_count_scope_items_status_check check (status in ('pending', 'assigned', 'recount_required', 'pending_review', 'adjusted', 'no_variance_closed', 'cancelled')),
  constraint cycle_count_scope_items_variance_shape_check check ((last_observed_quantity is null) = (variance_quantity is null)),
  constraint cycle_count_scope_items_adjusted_requires_review_check check (
    status <> 'adjusted' or (reviewed_by_auth_user_id is not null and reviewed_at is not null and review_reason is not null)
  )
);

comment on table app.cycle_count_scope_items is
  'ATW-020: one row per snapshotted app.inventory_balances dimension under a plan. snapshot_expected_quantity/snapshot_record_version are a real point-in-time READ snapshot (design note 4) -- never a reservation. reviewed_by_auth_user_id/reviewed_at/review_reason are reserved for a real adjusted resolution only (design note 7, cycle_count_scope_items_adjusted_requires_review_check) -- app.reject_cycle_count_variance never sets them.';

create unique index cycle_count_scope_items_active_balance_unique on app.cycle_count_scope_items (snapshot_balance_id)
  where status not in ('adjusted', 'no_variance_closed', 'cancelled');

comment on index app.cycle_count_scope_items_active_balance_unique is
  'ATW-020: the real, DB-enforced reservation/activity conflict guard (design note 3, Prompt 239 section 13) -- at most one in-flight cycle-count scope item per inventory balance dimension, across every plan in the tenant, at any time.';

create index cycle_count_scope_items_tenant_plan_status_idx on app.cycle_count_scope_items (tenant_id, plan_id, status);
create index cycle_count_scope_items_tenant_warehouse_assignee_idx on app.cycle_count_scope_items (tenant_id, warehouse_id, assigned_to_auth_user_id);

create function app.touch_cycle_count_scope_items_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger cycle_count_scope_items_touch_row
  before update on app.cycle_count_scope_items
  for each row
  execute function app.touch_cycle_count_scope_items_row();

-- 4. Observations -- append-only evidence, one row per submitted count/recount attempt.
create table app.cycle_count_observations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scope_item_id uuid not null references app.cycle_count_scope_items (id),
  attempt_number integer not null,
  observed_quantity numeric not null,
  observed_uom_code text not null references app.uoms (code),
  scanned_location_id uuid not null references app.warehouse_locations (id),
  scanned_item_master_id uuid not null references app.item_masters (id),
  scanned_lot_number text,
  scanned_serial_number text,
  idempotency_key text not null,
  counted_by_auth_user_id uuid references auth.users (id),
  counted_by_label text,
  counted_at timestamptz not null default now(),
  constraint cycle_count_observations_attempt_number_check check (attempt_number > 0),
  constraint cycle_count_observations_observed_quantity_check check (observed_quantity >= 0),
  constraint cycle_count_observations_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint cycle_count_observations_scope_item_attempt_unique unique (scope_item_id, attempt_number)
);

comment on table app.cycle_count_observations is
  'ATW-020: append-only evidence, one row per real (or idempotently replayed) app.record_cycle_count_observation call. observed_quantity=0 is a real, valid observation (Prompt 239 section 24 "zero is a valid observed quantity") -- never treated as missing. Never updated or deleted by any grant in this migration.';

create index cycle_count_observations_scope_item_idx on app.cycle_count_observations (scope_item_id);

-- 5. Plan mutations.

create function app.create_cycle_count_plan(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_method text,
  p_variance_threshold_pct numeric,
  p_recount_threshold_pct numeric,
  p_requires_separate_approver boolean,
  p_scope_filter_zone_id uuid,
  p_scope_filter_location_id uuid,
  p_scope_filter_item_master_id uuid,
  p_scope_filter_owner_account_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_existing app.cycle_count_plans;
  v_plan app.cycle_count_plans;
  v_method text;
  v_number text;
  v_zone app.warehouse_zones;
  v_location app.warehouse_locations;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to create a cycle count plan' using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot create a cycle count plan under warehouse %', p_actor_auth_user_id, p_warehouse_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before.
  select * into v_existing from app.cycle_count_plans where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  v_method := coalesce(p_method, 'full');
  if v_method not in ('full', 'abc', 'spot') then
    raise exception 'invalid_method: % is not a recognized cycle count method', v_method using errcode = 'check_violation';
  end if;
  if p_variance_threshold_pct is null or p_variance_threshold_pct < 0 then
    raise exception 'invalid_variance_threshold: variance_threshold_pct must be zero or greater' using errcode = 'check_violation';
  end if;
  if p_recount_threshold_pct is null or p_recount_threshold_pct < 0 then
    raise exception 'invalid_recount_threshold: recount_threshold_pct must be zero or greater' using errcode = 'check_violation';
  end if;

  if p_scope_filter_zone_id is not null then
    select * into v_zone from app.warehouse_zones where id = p_scope_filter_zone_id;
    if not found or v_zone.warehouse_id <> p_warehouse_id then
      raise exception 'scope_filter_zone_not_found: % is not a zone of warehouse %', p_scope_filter_zone_id, p_warehouse_id using errcode = 'check_violation';
    end if;
  end if;
  if p_scope_filter_location_id is not null then
    select * into v_location from app.warehouse_locations where id = p_scope_filter_location_id;
    if not found or v_location.warehouse_id <> p_warehouse_id then
      raise exception 'scope_filter_location_not_found: % is not a location of warehouse %', p_scope_filter_location_id, p_warehouse_id using errcode = 'check_violation';
    end if;
  end if;
  if p_scope_filter_item_master_id is not null and not exists (select 1 from app.item_masters where id = p_scope_filter_item_master_id and tenant_id = p_tenant_id) then
    raise exception 'scope_filter_item_master_not_found: % is not an item master of tenant %', p_scope_filter_item_master_id, p_tenant_id using errcode = 'check_violation';
  end if;
  if p_scope_filter_owner_account_id is not null and not exists (select 1 from app.accounts where id = p_scope_filter_owner_account_id and tenant_id = p_tenant_id) then
    raise exception 'scope_filter_owner_account_not_found: % is not an account of tenant %', p_scope_filter_owner_account_id, p_tenant_id using errcode = 'check_violation';
  end if;

  v_number := app.next_cycle_count_plan_number(p_tenant_id);

  begin
    insert into app.cycle_count_plans (
      tenant_id, warehouse_id, plan_number, method, variance_threshold_pct, recount_threshold_pct, requires_separate_approver,
      scope_filter_zone_id, scope_filter_location_id, scope_filter_item_master_id, scope_filter_owner_account_id, idempotency_key, created_by
    ) values (
      p_tenant_id, p_warehouse_id, v_number, v_method, p_variance_threshold_pct, p_recount_threshold_pct, coalesce(p_requires_separate_approver, true),
      p_scope_filter_zone_id, p_scope_filter_location_id, p_scope_filter_item_master_id, p_scope_filter_owner_account_id, p_idempotency_key, p_actor_label
    )
    returning * into v_plan;
  exception
    when unique_violation then
      select * into v_existing from app.cycle_count_plans where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent plan creation request', p_idempotency_key using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_cycle_count_plan',
    'app.cycle_count_plans', v_plan.id, 'success', null, null,
    jsonb_build_object('plan_number', v_number, 'warehouse_id', p_warehouse_id, 'method', v_method)
  );

  return v_plan;
end;
$$;

comment on function app.create_cycle_count_plan is
  'ATW-020: idempotent on (tenant_id, idempotency_key), including under a genuine race. status starts draft. Thresholds/requires_separate_approver are fixed here for the plan''s entire lifetime (design note 1) -- no update RPC exists.';

create function app.freeze_cycle_count_scope(
  p_plan_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns setof app.cycle_count_scope_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_plan app.cycle_count_plans;
  v_warehouse app.warehouses;
  v_balance app.inventory_balances;
  v_item app.item_masters;
  v_existing_scope_item app.cycle_count_scope_items;
  v_created_ids uuid[] := '{}';
  v_scope_item app.cycle_count_scope_items;
  v_can_see_expected boolean;
begin
  select * into v_plan from app.cycle_count_plans where id = p_plan_id for update;
  if not found then
    raise exception 'plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_plan.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot freeze plan %', p_actor_auth_user_id, p_plan_id using errcode = 'insufficient_privilege';
  end if;

  if v_plan.status <> 'draft' then
    raise exception 'freeze_already_done: plan % is % -- only a draft plan may be frozen', p_plan_id, v_plan.status using errcode = 'check_violation';
  end if;
  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version using errcode = 'check_violation';
  end if;

  -- Design note 3/9: locks each matching balance row FOR UPDATE as it scans -- a real
  -- point-in-time snapshot, and the structural mechanism that serializes two
  -- concurrent freezes against an overlapping balance set. Only existing app.
  -- inventory_balances rows (status='on_hand') are eligible -- a location the ledger
  -- has never touched is out of scope (design note 9), a deliberate boundary.
  for v_balance in
    select b.* from app.inventory_balances b
    where b.tenant_id = v_plan.tenant_id
      and b.warehouse_id = v_plan.warehouse_id
      and b.status = 'on_hand'
      and (v_plan.scope_filter_location_id is null or b.location_id = v_plan.scope_filter_location_id)
      and (v_plan.scope_filter_item_master_id is null or b.item_master_id = v_plan.scope_filter_item_master_id)
      and (v_plan.scope_filter_owner_account_id is null or b.owner_account_id = v_plan.scope_filter_owner_account_id)
      and (
        v_plan.scope_filter_zone_id is null
        or exists (select 1 from app.warehouse_locations l where l.id = b.location_id and l.zone_id = v_plan.scope_filter_zone_id)
      )
    order by b.id
    for update
  loop
    select * into v_existing_scope_item from app.cycle_count_scope_items
      where snapshot_balance_id = v_balance.id and status not in ('adjusted', 'no_variance_closed', 'cancelled');
    if found then
      raise exception 'balance_already_in_active_count: balance % is already part of an active cycle count scope item %', v_balance.id, v_existing_scope_item.id
        using errcode = 'check_violation';
    end if;

    select * into v_item from app.item_masters where id = v_balance.item_master_id;

    -- Design note 7 (defense-in-depth, findings review): the preceding scan-and-check
    -- plus this loop's own FOR UPDATE lock on each matching balance row make this race
    -- structurally unreachable today, but a raw unique_violation is still translated to
    -- the same friendly error the pre-check above raises, rather than left to propagate
    -- unhandled -- identical convention to app.create_cycle_count_plan/app.record_
    -- cycle_count_observation's own idempotency-key unique_violation handlers.
    begin
      insert into app.cycle_count_scope_items (
        tenant_id, plan_id, warehouse_id, owner_account_id, item_master_id, location_id, lot_number, serial_number,
        uom_code, snapshot_balance_id, snapshot_expected_quantity, snapshot_record_version
      ) values (
        v_plan.tenant_id, p_plan_id, v_plan.warehouse_id, v_balance.owner_account_id, v_balance.item_master_id, v_balance.location_id, v_balance.lot_number, v_balance.serial_number,
        v_item.base_uom_code, v_balance.id, v_balance.on_hand, v_balance.record_version
      )
      returning * into v_scope_item;
    exception
      when unique_violation then
        select * into v_existing_scope_item from app.cycle_count_scope_items
          where snapshot_balance_id = v_balance.id and status not in ('adjusted', 'no_variance_closed', 'cancelled');
        if found then
          raise exception 'balance_already_in_active_count: balance % is already part of an active cycle count scope item % (concurrent freeze)', v_balance.id, v_existing_scope_item.id
            using errcode = 'check_violation';
        end if;
        raise exception 'balance_already_in_active_count: balance % is already part of an active cycle count scope item (concurrent freeze)', v_balance.id
          using errcode = 'check_violation';
    end;

    v_created_ids := v_created_ids || v_scope_item.id;
  end loop;

  update app.cycle_count_plans set status = 'active', frozen_at = now() where id = p_plan_id;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'freeze_cycle_count_scope',
    'app.cycle_count_plans', p_plan_id, 'success', null, null, jsonb_build_object('scope_item_count', coalesce(array_length(v_created_ids, 1), 0))
  );

  -- Findings review (HIGH #1/#3): blind-count redaction (design note 6) applies to
  -- every RPC that returns a scope item row, mutation or read alike -- a plain
  -- OPS:Edit-only counter must never see snapshot_expected_quantity/variance_quantity/
  -- variance_pct/snapshot_record_version, including via a self-triggered freeze.
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'Override')).allowed;
  for v_scope_item in select * from app.cycle_count_scope_items where id = any(v_created_ids) loop
    if not v_can_see_expected then
      v_scope_item.snapshot_expected_quantity := null;
      v_scope_item.variance_quantity := null;
      v_scope_item.variance_pct := null;
      v_scope_item.snapshot_record_version := null;
    end if;
    return next v_scope_item;
  end loop;
  return;
end;
$$;

comment on function app.freeze_cycle_count_scope is
  'ATW-020: draft -> active. Snapshots every matching on-hand app.inventory_balances row under the plan''s own warehouse (and scope filters), locking each FOR UPDATE as it scans (design note 3/9) -- a real point-in-time snapshot, and the mechanism that serializes concurrent freezes against an overlapping balance set. A zero-match freeze is a valid, non-error outcome (an empty returned set), not an error. Applies blind-count redaction (design note 6) to the returned rows -- an OPS:Edit-only actor freezing the scope themselves never sees snapshot_expected_quantity et al, closing the self-freeze disclosure gap.';

create function app.cancel_cycle_count_plan(
  p_plan_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_plan app.cycle_count_plans;
  v_warehouse app.warehouses;
  v_scope_item app.cycle_count_scope_items;
  v_cancelled_count integer := 0;
begin
  select * into v_plan from app.cycle_count_plans where id = p_plan_id for update;
  if not found then
    raise exception 'plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_plan.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot cancel plan %', p_actor_auth_user_id, p_plan_id using errcode = 'insufficient_privilege';
  end if;

  if v_plan.status not in ('draft', 'active') then
    raise exception 'invalid_transition: plan % is % -- only a draft or active plan may be cancelled', p_plan_id, v_plan.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a cycle count plan' using errcode = 'check_violation';
  end if;
  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version using errcode = 'check_violation';
  end if;

  -- Design note (Prompt 239 section 32): a real loop, each row individually locked and
  -- updated -- never a bare bulk UPDATE -- so each scope item's own touch trigger fires
  -- correctly. Approved (adjusted) movements are permanent and never touched here.
  for v_scope_item in
    select * from app.cycle_count_scope_items where plan_id = p_plan_id and status not in ('adjusted', 'no_variance_closed', 'cancelled') for update
  loop
    update app.cycle_count_scope_items set status = 'cancelled' where id = v_scope_item.id;
    v_cancelled_count := v_cancelled_count + 1;
  end loop;

  update app.cycle_count_plans set status = 'cancelled' where id = p_plan_id returning * into v_plan;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_cycle_count_plan',
    'app.cycle_count_plans', v_plan.id, 'success', p_reason, null, jsonb_build_object('scope_items_cancelled', v_cancelled_count)
  );

  return v_plan;
end;
$$;

comment on function app.cancel_cycle_count_plan is
  'ATW-020: draft/active -> cancelled. Every unresolved scope item under the plan is individually locked and cancelled in a real loop (never a bulk UPDATE) -- adjusted/no_variance_closed/already-cancelled items are left exactly as-is; approved movements are permanent (Prompt 239 section 32).';

create function app.close_cycle_count_plan(
  p_plan_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_plans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_plan app.cycle_count_plans;
  v_warehouse app.warehouses;
  v_unresolved_count integer;
begin
  select * into v_plan from app.cycle_count_plans where id = p_plan_id for update;
  if not found then
    raise exception 'plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_plan.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot close plan %', p_actor_auth_user_id, p_plan_id using errcode = 'insufficient_privilege';
  end if;

  if v_plan.status <> 'active' then
    raise exception 'invalid_transition: plan % is % -- only an active plan may be closed', p_plan_id, v_plan.status using errcode = 'check_violation';
  end if;
  if v_plan.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count plan % expected version % but found %', p_plan_id, p_expected_version, v_plan.record_version using errcode = 'check_violation';
  end if;

  select count(*) into v_unresolved_count from app.cycle_count_scope_items
    where plan_id = p_plan_id and status not in ('adjusted', 'no_variance_closed', 'cancelled');
  if v_unresolved_count > 0 then
    raise exception 'plan_has_unresolved_scope_items: plan % has % unresolved scope item(s) -- every scope item must be adjusted, no_variance_closed or cancelled before the plan may close', p_plan_id, v_unresolved_count
      using errcode = 'check_violation';
  end if;

  update app.cycle_count_plans set status = 'closed', closed_at = now() where id = p_plan_id returning * into v_plan;

  perform app.capture_audit_event(
    v_plan.tenant_id, p_actor_auth_user_id, p_actor_label, 'close_cycle_count_plan',
    'app.cycle_count_plans', v_plan.id, 'success', null, null, null
  );

  return v_plan;
end;
$$;

comment on function app.close_cycle_count_plan is
  'ATW-020: active -> closed. Requires every scope item under the plan to be adjusted/no_variance_closed/cancelled (plan_has_unresolved_scope_items otherwise, naming the exact unresolved count).';

-- 6. Scope item mutations.

create function app.assign_cycle_count_scope_item(
  p_scope_item_id uuid,
  p_assignee_auth_user_id uuid,
  p_assignee_label text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_scope_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_can_see_expected boolean;
begin
  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot assign scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to assign scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  if v_item.status not in ('pending', 'recount_required') then
    raise exception 'task_not_assignable: scope item % is % -- only a pending or recount_required item may be assigned', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;

  update app.cycle_count_scope_items set
    status = 'assigned', assigned_to_auth_user_id = p_assignee_auth_user_id, assigned_to_label = p_assignee_label, assigned_at = now()
  where id = p_scope_item_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_cycle_count_scope_item',
    'app.cycle_count_scope_items', v_item.id, 'success', null, null, jsonb_build_object('assigned_to', p_assignee_label)
  );

  -- Findings review (HIGH #1/#3): blind-count redaction (design note 6) -- a plain
  -- OPS:Edit-only counter self-assigning a scope item must never learn the true
  -- expected quantity before ever entering a count.
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
  if not v_can_see_expected then
    v_item.snapshot_expected_quantity := null;
    v_item.variance_quantity := null;
    v_item.variance_pct := null;
    v_item.snapshot_record_version := null;
  end if;

  return v_item;
end;
$$;

comment on function app.assign_cycle_count_scope_item is
  'ATW-020: pending|recount_required -> assigned. assigned_to is overwritten even on a recount reassignment (a fresh or same assignee) -- the only way this migration lets a scope item change assignee. Applies blind-count redaction (design note 6) to the returned row.';

create function app.record_cycle_count_observation(
  p_scope_item_id uuid,
  p_observed_quantity numeric,
  p_observed_uom_code text,
  p_scanned_location_id uuid,
  p_scanned_item_master_id uuid,
  p_scanned_lot_number text,
  p_scanned_serial_number text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_scope_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_existing_observation app.cycle_count_observations;
  v_converted_quantity numeric;
  v_new_attempt integer;
  v_variance numeric;
  v_variance_pct numeric;
  v_plan app.cycle_count_plans;
  v_new_status text;
  v_was_first_attempt boolean;
  v_can_see_expected boolean;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to record a cycle count observation' using errcode = 'check_violation';
  end if;

  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot record an observation for scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to record an observation for scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before. Findings review (MEDIUM #5): matches on (tenant_id, idempotency_key) alone
  -- is not enough -- a key collision against a DIFFERENT scope item must be rejected,
  -- never silently treated as "nothing to do" for the caller's own real target item.
  select * into v_existing_observation from app.cycle_count_observations where tenant_id = v_item.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing_observation.scope_item_id <> p_scope_item_id then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different observation for scope item % (not %)', p_idempotency_key, v_existing_observation.scope_item_id, p_scope_item_id
        using errcode = 'unique_violation';
    end if;
    -- Findings review (HIGH #1/#3): blind-count redaction (design note 6) applies to
    -- the idempotent-replay response identically to a fresh submission's own response.
    v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
    if not v_can_see_expected then
      v_item.snapshot_expected_quantity := null;
      v_item.variance_quantity := null;
      v_item.variance_pct := null;
      v_item.snapshot_record_version := null;
    end if;
    return v_item;
  end if;

  if v_item.status <> 'assigned' then
    raise exception 'task_not_assigned: scope item % is % -- only an assigned item may be counted', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.assigned_to_auth_user_id <> p_actor_auth_user_id then
    raise exception 'not_scope_item_claimant: identity % is not the assigned counter of scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;
  if p_observed_quantity is null or p_observed_quantity < 0 then
    raise exception 'invalid_quantity: observed quantity must be zero or greater' using errcode = 'check_violation';
  end if;

  -- Design note: scan verification is data-integrity only, never an authorization
  -- bypass -- authority was already fully established above.
  if p_scanned_location_id is distinct from v_item.location_id then
    raise exception 'location_mismatch: scanned location % does not match scope item %''s own location %', p_scanned_location_id, p_scope_item_id, v_item.location_id using errcode = 'check_violation';
  end if;
  if p_scanned_item_master_id is distinct from v_item.item_master_id then
    raise exception 'item_mismatch: scanned item % does not match scope item %''s own item %', p_scanned_item_master_id, p_scope_item_id, v_item.item_master_id using errcode = 'check_violation';
  end if;
  if v_item.lot_number is not null and coalesce(p_scanned_lot_number, '') <> v_item.lot_number then
    raise exception 'lot_mismatch: scanned lot % does not match scope item %''s own lot %', p_scanned_lot_number, p_scope_item_id, v_item.lot_number using errcode = 'check_violation';
  end if;
  if v_item.serial_number is not null and coalesce(p_scanned_serial_number, '') <> v_item.serial_number then
    raise exception 'serial_mismatch: scanned serial % does not match scope item %''s own serial %', p_scanned_serial_number, p_scope_item_id, v_item.serial_number using errcode = 'check_violation';
  end if;

  -- Converts to the scope item's own governed uom_code (its item's base_uom_code at
  -- freeze time) when the caller scanned in a different, but convertible, UOM.
  -- app.convert_uom_quantity raises uom_conversion_not_registered naturally when no
  -- path exists -- deliberately allowed to propagate, never guessed.
  v_converted_quantity := app.convert_uom_quantity(p_observed_quantity, p_observed_uom_code, v_item.uom_code);

  v_was_first_attempt := (v_item.count_attempt_number = 0);
  v_new_attempt := v_item.count_attempt_number + 1;

  begin
    insert into app.cycle_count_observations (
      tenant_id, scope_item_id, attempt_number, observed_quantity, observed_uom_code, scanned_location_id, scanned_item_master_id,
      scanned_lot_number, scanned_serial_number, idempotency_key, counted_by_auth_user_id, counted_by_label
    ) values (
      v_item.tenant_id, p_scope_item_id, v_new_attempt, p_observed_quantity, p_observed_uom_code, p_scanned_location_id, p_scanned_item_master_id,
      p_scanned_lot_number, p_scanned_serial_number, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      select * into v_existing_observation from app.cycle_count_observations where tenant_id = v_item.tenant_id and idempotency_key = p_idempotency_key;
      -- Findings review (MEDIUM #5): the same cross-item collision check applies to the
      -- genuine-race path, not only the pre-check above.
      if found and v_existing_observation.scope_item_id = p_scope_item_id then
        v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
        if not v_can_see_expected then
          v_item.snapshot_expected_quantity := null;
          v_item.variance_quantity := null;
          v_item.variance_pct := null;
          v_item.snapshot_record_version := null;
        end if;
        return v_item;
      end if;
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent observation request', p_idempotency_key using errcode = 'unique_violation';
  end;

  v_variance := v_converted_quantity - v_item.snapshot_expected_quantity;
  v_variance_pct := case
    when v_item.snapshot_expected_quantity = 0 then (case when v_converted_quantity = 0 then 0 else 100 end)
    else abs(v_variance) / v_item.snapshot_expected_quantity * 100
  end;

  select * into v_plan from app.cycle_count_plans where id = v_item.plan_id;

  -- Design note: exactly one recount cycle is ever possible -- a first attempt (was_
  -- first_attempt) whose variance exceeds the plan's own recount_threshold_pct goes to
  -- recount_required; every subsequent attempt (2nd+) can only land on pending_review
  -- or no_variance_closed, never recount_required again.
  --
  -- Findings review (MEDIUM #2): variance_threshold_pct is the plan's own configured
  -- materiality tolerance -- a nonzero variance that still falls at or below it is
  -- immaterial by the plan's own definition and auto-resolves exactly like a zero
  -- variance (no manual review, no ledger adjustment posted), checked before the
  -- recount escalation so a generous variance_threshold_pct always wins over a
  -- stricter recount_threshold_pct for the same observation.
  v_new_status := case
    when v_variance = 0 then 'no_variance_closed'
    when abs(v_variance_pct) <= v_plan.variance_threshold_pct then 'no_variance_closed'
    when abs(v_variance_pct) > v_plan.recount_threshold_pct and v_was_first_attempt then 'recount_required'
    else 'pending_review'
  end;

  update app.cycle_count_scope_items set
    count_attempt_number = v_new_attempt,
    last_observed_quantity = v_converted_quantity,
    variance_quantity = v_variance,
    variance_pct = v_variance_pct,
    status = v_new_status
  where id = p_scope_item_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_cycle_count_observation',
    'app.cycle_count_scope_items', v_item.id, 'success', null, null,
    jsonb_build_object('attempt_number', v_new_attempt, 'observed_quantity', v_converted_quantity, 'variance_quantity', v_variance, 'status', v_new_status)
  );

  -- Findings review (HIGH #1/#3): blind-count redaction (design note 6) -- the RPC a
  -- counter is required to call to submit their own blind count must never hand back
  -- the true expected quantity/variance in the same response.
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
  if not v_can_see_expected then
    v_item.snapshot_expected_quantity := null;
    v_item.variance_quantity := null;
    v_item.variance_pct := null;
    v_item.snapshot_record_version := null;
  end if;

  return v_item;
end;
$$;

comment on function app.record_cycle_count_observation is
  'ATW-020: idempotent per-observation-event on (tenant_id, idempotency_key) -- a key reused against a DIFFERENT scope item raises idempotency_key_conflict rather than silently no-op''ing on the wrong item. Only the scope item''s own assigned counter may submit (not_scope_item_claimant otherwise). observed_quantity=0 is a real, valid observation, never an error. A variance at or below the plan''s own variance_threshold_pct (materiality tolerance) resolves directly to no_variance_closed, identically to an exact-zero variance. Otherwise: 1st attempt within the recount threshold resolves to pending_review; 1st attempt beyond it escalates to recount_required; every subsequent attempt only ever resolves to pending_review or no_variance_closed. Applies blind-count redaction (design note 6) to the returned row, including both idempotent-replay short-circuits.';

create function app.approve_cycle_count_variance(
  p_scope_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_scope_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_plan app.cycle_count_plans;
  v_last_observation app.cycle_count_observations;
  v_balance app.inventory_balances;
  v_movement app.inventory_movements;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to approve a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot approve scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to approve scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before. Never re-posts a second ledger movement for an already-adjusted item.
  if v_item.status = 'adjusted' and v_item.adjustment_movement_id is not null then
    return v_item;
  end if;

  if v_item.status <> 'pending_review' then
    raise exception 'task_not_pending_review: scope item % is % -- only a pending_review item may be approved', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to approve a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_plan from app.cycle_count_plans where id = v_item.plan_id;

  if v_plan.requires_separate_approver then
    select * into v_last_observation from app.cycle_count_observations
      where scope_item_id = p_scope_item_id
      order by attempt_number desc
      limit 1;
    if found and v_last_observation.counted_by_auth_user_id = p_actor_auth_user_id then
      raise exception 'self_approval_not_allowed: identity % submitted the most recent count for scope item % and may not also approve its own variance', p_actor_auth_user_id, p_scope_item_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Design note 4: stale-snapshot detection -- re-lock the CURRENT balance row and
  -- compare its live record_version against the snapshot's own captured version.
  select * into v_balance from app.inventory_balances where id = v_item.snapshot_balance_id for update;
  if not found then
    raise exception 'balance_not_found: snapshot balance % no longer exists', v_item.snapshot_balance_id using errcode = 'no_data_found';
  end if;
  if v_balance.record_version <> v_item.snapshot_record_version then
    raise exception 'balance_changed_since_snapshot: balance % has changed since scope item %''s own snapshot was taken (expected version %, found %) -- cancel this scope item and refreeze rather than post a now-incorrect adjustment', v_item.snapshot_balance_id, p_scope_item_id, v_item.snapshot_record_version, v_balance.record_version
      using errcode = 'check_violation';
  end if;

  -- The one and only place a cycle count ever changes on_hand -- via the canonical
  -- app.post_inventory_movement primitive, never a direct balance write (Prompt 239
  -- section 24, this task's own objective).
  v_movement := app.post_inventory_movement(
    v_item.tenant_id, v_item.warehouse_id, 'adjustment', 'cycle_count', p_scope_item_id, p_idempotency_key, p_reason,
    jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_item.owner_account_id, 'item_master_id', v_item.item_master_id, 'location_id', v_item.location_id,
      'uom_code', v_item.uom_code, 'signed_quantity', v_item.variance_quantity, 'lot_number', v_item.lot_number, 'serial_number', v_item.serial_number, 'status', 'on_hand'
    )),
    p_actor_auth_user_id, p_actor_label
  );

  -- Findings review (HIGH #4): app.post_inventory_movement's own idempotency dedups
  -- purely on (tenant_id, idempotency_key) -- it has no way to know this call's own
  -- scope item. If p_idempotency_key was already used by a DIFFERENT scope item's
  -- approval, the call above silently returns THAT item's already-posted movement
  -- unchanged. Attaching it to the CURRENT item here would mark it adjusted with a
  -- movement that reflects a completely different item/location/lot/quantity, and its
  -- own real variance would never be posted -- reject instead, exactly like a genuine
  -- idempotency-key collision anywhere else in this migration.
  if v_movement.source_type <> 'cycle_count' or v_movement.source_id <> p_scope_item_id then
    raise exception 'idempotency_key_conflict: idempotency key % was already used by a different movement (source_type=%, source_id=%), not scope item %', p_idempotency_key, v_movement.source_type, v_movement.source_id, p_scope_item_id
      using errcode = 'unique_violation';
  end if;

  update app.cycle_count_scope_items set
    adjustment_movement_id = v_movement.id,
    status = 'adjusted',
    reviewed_by_auth_user_id = p_actor_auth_user_id,
    reviewed_by_label = p_actor_label,
    reviewed_at = now(),
    review_reason = p_reason
  where id = p_scope_item_id
  returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_cycle_count_variance',
    'app.cycle_count_scope_items', v_item.id, 'success', p_reason, null,
    jsonb_build_object('movement_id', v_movement.id, 'variance_quantity', v_item.variance_quantity)
  );

  return v_item;
end;
$$;

comment on function app.approve_cycle_count_variance is
  'ATW-020: pending_review -> adjusted, posting exactly one app.post_inventory_movement (movement_type=adjustment, source_type=cycle_count, design note 4/8) -- never a direct balance write. Idempotent: a same-item retry after success returns the identical row unchanged, never re-posts. Rejects self_approval_not_allowed when the plan requires a separate approver and the acting identity submitted the most recent count. Rejects balance_changed_since_snapshot if the underlying balance moved between freeze and approval. Rejects idempotency_key_conflict if p_idempotency_key was already used by a DIFFERENT scope item''s approval -- never attaches another item''s movement to this one.';

create function app.reject_cycle_count_variance(
  p_scope_item_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_scope_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_plan app.cycle_count_plans;
  v_last_observation app.cycle_count_observations;
begin
  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reject scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to reject scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  if v_item.status <> 'pending_review' then
    raise exception 'task_not_pending_review: scope item % is % -- only a pending_review item may be rejected', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reject a cycle count variance' using errcode = 'check_violation';
  end if;

  select * into v_plan from app.cycle_count_plans where id = v_item.plan_id;
  if v_plan.requires_separate_approver then
    select * into v_last_observation from app.cycle_count_observations
      where scope_item_id = p_scope_item_id
      order by attempt_number desc
      limit 1;
    if found and v_last_observation.counted_by_auth_user_id = p_actor_auth_user_id then
      raise exception 'self_approval_not_allowed: identity % submitted the most recent count for scope item % and may not also reject its own variance', p_actor_auth_user_id, p_scope_item_id
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Design note 7: reviewed_by_auth_user_id/reviewed_at/review_reason are reserved for
  -- a real adjusted resolution (cycle_count_scope_items_adjusted_requires_review_check)
  -- -- never set here. Who rejected and why is captured in the audit event below.
  update app.cycle_count_scope_items set status = 'recount_required' where id = p_scope_item_id returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'reject_cycle_count_variance',
    'app.cycle_count_scope_items', v_item.id, 'success', p_reason, null, null
  );

  return v_item;
end;
$$;

comment on function app.reject_cycle_count_variance is
  'ATW-020: pending_review -> recount_required (design note 7) -- sends the item back for a fresh count rather than silently discarding the variance. Never sets reviewed_by/reviewed_at/review_reason (reserved for a real adjusted resolution).';

create function app.cancel_cycle_count_scope_item(
  p_scope_item_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.cycle_count_scope_items
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
begin
  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id for update;
  if not found then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot cancel scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to cancel scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority is confirmed above, never before.
  if v_item.status = 'cancelled' then
    return v_item;
  end if;
  if v_item.status in ('adjusted', 'no_variance_closed') then
    raise exception 'scope_item_already_resolved: scope item % is % -- a resolved item may never be cancelled (approved movements are permanent, Prompt 239 section 32)', p_scope_item_id, v_item.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a cycle count scope item' using errcode = 'check_violation';
  end if;
  if v_item.record_version <> p_expected_version then
    raise exception 'stale_version: cycle count scope item % expected version % but found %', p_scope_item_id, p_expected_version, v_item.record_version using errcode = 'check_violation';
  end if;

  update app.cycle_count_scope_items set status = 'cancelled' where id = p_scope_item_id returning * into v_item;

  perform app.capture_audit_event(
    v_item.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_cycle_count_scope_item',
    'app.cycle_count_scope_items', v_item.id, 'success', p_reason, null, null
  );

  return v_item;
end;
$$;

comment on function app.cancel_cycle_count_scope_item is
  'ATW-020: any pre-resolution status -> cancelled. Idempotent no-op if already cancelled. Rejects scope_item_already_resolved for an adjusted or no_variance_closed item -- a resolved item, especially one with a real posted movement, is never reversible through this path.';

-- 7. Reads. Every RPC returning an app.cycle_count_scope_items row applies the blind-
-- count redaction rule (design note 6) -- computed server-side from the actor's own
-- real RBAC grant, never a caller-supplied parameter.

create function app.get_cycle_count_plan(p_plan_id uuid, p_actor_auth_user_id uuid)
returns app.cycle_count_plans
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_plan app.cycle_count_plans;
  v_warehouse app.warehouses;
begin
  select * into v_plan from app.cycle_count_plans where id = p_plan_id;
  if not found then
    raise exception 'plan_not_found: %', p_plan_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_plan.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_plan.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_plan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_plan.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view plan %', p_actor_auth_user_id, p_plan_id using errcode = 'insufficient_privilege';
  end if;

  return v_plan;
end;
$$;

comment on function app.get_cycle_count_plan is
  'ATW-020: OPS:View + record-scope by the plan''s own warehouse (design note 5) -- a plan itself has no single owner_account_id, unlike a scope item.';

create function app.list_cycle_count_plans(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.cycle_count_plans
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select p.* from app.cycle_count_plans p
  join app.warehouses w on w.id = p.warehouse_id
  where p.tenant_id = p_tenant_id
    and (p_warehouse_id is null or p.warehouse_id = p_warehouse_id)
    and (p_status_filter is null or p.status = p_status_filter)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
  order by p.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_cycle_count_plans is
  'ATW-020: bounded read (p_limit default 50, hard-capped 200 regardless of what the caller requests).';

create function app.get_cycle_count_scope_item(p_scope_item_id uuid, p_actor_auth_user_id uuid)
returns app.cycle_count_scope_items
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_item app.cycle_count_scope_items;
  v_can_see_expected boolean;
begin
  select * into v_item from app.cycle_count_scope_items where id = p_scope_item_id;
  if not found then
    raise exception 'scope_item_not_found: %', p_scope_item_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_item.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_item.warehouse_id, v_item.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_item.tenant_id, v_item.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view scope item %', p_actor_auth_user_id, p_scope_item_id using errcode = 'insufficient_privilege';
  end if;

  -- Design note 6: blind-count redaction, computed server-side from the actor's own
  -- real RBAC grant -- there is no caller-supplied parameter that can defeat this.
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, v_item.tenant_id, 'OPS', 'Override')).allowed;
  if not v_can_see_expected then
    v_item.snapshot_expected_quantity := null;
    v_item.variance_quantity := null;
    v_item.variance_pct := null;
    v_item.snapshot_record_version := null;
  end if;

  return v_item;
end;
$$;

comment on function app.get_cycle_count_scope_item is
  'ATW-020: OPS:View + app.wms_pick_record_scope_ok + app.actor_can_view_owner_scoped_row (owner-scoped, unlike a plan). Applies blind-count redaction (design note 6) -- a plain OPS:Edit-only counter never sees snapshot_expected_quantity/variance_quantity/variance_pct/snapshot_record_version; an OPS:Override supervisor always does.';

create function app.list_cycle_count_scope_items(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_plan_id uuid default null,
  p_status_filter text default null,
  p_assigned_to_auth_user_id uuid default null,
  p_limit integer default 50
)
returns setof app.cycle_count_scope_items
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
  v_can_see_expected boolean;
  v_row app.cycle_count_scope_items;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_can_see_expected := (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'Override')).allowed;

  for v_row in
    select s.* from app.cycle_count_scope_items s
    where s.tenant_id = p_tenant_id
      and (p_plan_id is null or s.plan_id = p_plan_id)
      and (p_status_filter is null or s.status = p_status_filter)
      and (p_assigned_to_auth_user_id is null or s.assigned_to_auth_user_id = p_assigned_to_auth_user_id)
      and app.wms_pick_record_scope_ok(p_actor_auth_user_id, s.warehouse_id, s.owner_account_id::text)
      and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, s.owner_account_id)
    order by s.created_at desc
    limit v_limit
  loop
    if not v_can_see_expected then
      v_row.snapshot_expected_quantity := null;
      v_row.variance_quantity := null;
      v_row.variance_pct := null;
      v_row.snapshot_record_version := null;
    end if;
    return next v_row;
  end loop;
  return;
end;
$$;

comment on function app.list_cycle_count_scope_items is
  'ATW-020: bounded read (p_limit default 50, hard-capped 200), owner-scoped, applying the identical blind-count redaction rule (design note 6) row by row.';

create function app.list_cycle_count_observations(p_scope_item_id uuid, p_actor_auth_user_id uuid)
returns setof app.cycle_count_observations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- Reuses app.get_cycle_count_scope_item for its own authority/record-scope/owner-
  -- scope gate rather than duplicating the checks (mirrors app.list_wms_pick_task_
  -- confirmations, ATW-017). This table never stores expected/variance values, only
  -- what was actually scanned/observed -- safe to show in full, no redaction needed.
  perform app.get_cycle_count_scope_item(p_scope_item_id, p_actor_auth_user_id);
  return query select * from app.cycle_count_observations where scope_item_id = p_scope_item_id order by attempt_number;
end;
$$;

-- 8. RLS -- record scope AND owner scope enforced in the database, not UI-only.

alter table app.cycle_count_plans enable row level security;

create policy cycle_count_plans_select_scoped on app.cycle_count_plans
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = cycle_count_plans.warehouse_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.cycle_count_scope_items enable row level security;

create policy cycle_count_scope_items_select_scoped on app.cycle_count_scope_items
  for select to authenticated
  using (
    app.wms_pick_record_scope_ok(auth.uid(), cycle_count_scope_items.warehouse_id, cycle_count_scope_items.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(auth.uid(), cycle_count_scope_items.tenant_id, cycle_count_scope_items.owner_account_id)
  );

alter table app.cycle_count_observations enable row level security;

create policy cycle_count_observations_select_scoped on app.cycle_count_observations
  for select to authenticated
  using (
    exists (
      select 1 from app.cycle_count_scope_items s
      where s.id = cycle_count_observations.scope_item_id
        and app.wms_pick_record_scope_ok(auth.uid(), s.warehouse_id, s.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row(auth.uid(), s.tenant_id, s.owner_account_id)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.cycle_count_plans, app.cycle_count_scope_items, app.cycle_count_observations to authenticated, service_role;
grant insert, update, delete on app.cycle_count_plans, app.cycle_count_scope_items, app.cycle_count_observations to service_role;
grant insert, update on app.cycle_count_plan_number_counters to service_role;

grant execute on function app.next_cycle_count_plan_number(uuid) to service_role;
grant execute on function app.create_cycle_count_plan(uuid, uuid, text, numeric, numeric, boolean, uuid, uuid, uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.freeze_cycle_count_scope(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_cycle_count_plan(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.close_cycle_count_plan(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.assign_cycle_count_scope_item(uuid, uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.record_cycle_count_observation(uuid, numeric, text, uuid, uuid, text, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.approve_cycle_count_variance(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.reject_cycle_count_variance(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_cycle_count_scope_item(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_cycle_count_plan(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_cycle_count_plans(uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.get_cycle_count_scope_item(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_cycle_count_scope_items(uuid, uuid, uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_cycle_count_observations(uuid, uuid) to authenticated, service_role;
