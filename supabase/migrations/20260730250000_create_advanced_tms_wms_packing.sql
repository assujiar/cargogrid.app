-- Advanced TMS/WMS capability ATW-018 (CG-S10-ATW-018, Prompt 237, "WMS Packing" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). Implements this
-- prompt's own §4 objective: "scan-verified packing that groups picked inventory into
-- traceable packages with measured attributes, QC and outbound readiness."
--
-- Direct upstream (Prompt 237 §9: "ATW-236; label/barcode contract later extended by
-- ATW-240" -- no circular dependency this time, per this session's own briefing):
-- ATW-017 (WMS Picking -- app.wms_pick_tasks/app.wms_pick_task_confirmations,
-- consumed directly, never re-derived; app.wms_pick_record_scope_ok, reused directly
-- in this migration's own RLS policies rather than re-derived a third time). This
-- migration never mutates app.wms_pick_tasks/app.inventory_balances/app.inventory_
-- movements at all -- packing groups ALREADY-PICKED, already-staged stock into
-- packages; it posts no ledger movement of its own (design note 0, disclosed bound;
-- Prompt 238/ATW-019's own later ship-confirm/inventory-issue job is the first point
-- physical stock actually leaves the warehouse).
--
-- Design boundary (disclosed):
--
-- 0. **No inventory ledger interaction (a disclosed scope bound, not an oversight).**
--    Prompt 237 §4's own objective is "groups picked inventory into traceable
--    packages" -- picked stock has already physically moved to a staging location via
--    `app.confirm_wms_pick_task` (ATW-017); packing never relocates it further and
--    never calls `app.post_inventory_movement`. `app.wms_pick_tasks.picked_quantity`
--    is read-only, authoritative "how much of this task now sits, physically picked,
--    ready to pack" -- this migration's own job is exclusively to track how much of
--    THAT already-picked quantity has been assigned into a package, never to move or
--    consume it. Prompt 237 §9's own note that `app.uoms.unit_category` is
--    "deliberately narrow... discrete packaging/handling units (box/carton/pallet)
--    are not a UOM here, deferred to Prompt 237" (`ATW-011A`'s own migration header)
--    is resolved here via a real, bounded `package_type` CHECK enum column on `app.
--    wms_packages` (design note 2) -- never as a new `app.uoms` row (a box is not a
--    unit of measure of a quantity; it is a container).
-- 1. **Packing is organized as ONE lightweight, state-machine-free packing task per
--    outbound order (`app.wms_packing_tasks`, `unique (tenant_id, outbound_order_id)`
--    in addition to the standard `unique (tenant_id, idempotency_key)`), never one
--    task per package and never a caller-opaque array.** Mirrors `ATW-017`'s own
--    design note 2 choice for `app.wms_pick_waves` one level up: a packing task
--    carries no `status` column at all -- its own completion state is always DERIVED
--    by querying its member `app.wms_packages` rows' own `status`, never tracked as a
--    second, potentially-inconsistent source of truth. Chosen over "one task per
--    package" because Prompt 237 §21's own main flow is singular ("packer starts
--    ASSIGNED TASK, scans picked stock into packageS" -- plural packages, one task),
--    and chosen over a caller-opaque array because every real state change in this
--    capability (add/remove line, measure, QC, seal, confirm, reopen) is scoped to
--    exactly one PACKAGE, never to the task header -- an array would just be a second,
--    redundant place those same package ids live.
-- 2. **The package/container hierarchy (Prompt 237 §13/§24): a single self-referencing
--    `parent_package_id` on `app.wms_packages`, real and structurally cycle-safe by
--    TWO complementary mechanisms.** (a) At CREATION (`app.create_wms_package`) a
--    cycle is structurally impossible by construction -- a new package's own `id` is
--    server-generated (`gen_random_uuid()`) and unknowable to the caller in advance, so
--    a supplied `p_parent_package_id` can only ever reference an ALREADY-EXISTING
--    package, and the existing package graph is already acyclic (proved inductively:
--    the very first package has no parent; every subsequent insert only ever adds a
--    new leaf onto an already-acyclic graph) -- exactly `app.org_units`' own
--    insertion-order-invariant precedent, reused directly rather than re-derived. (b)
--    The one operation that COULD otherwise introduce a real cycle -- moving an
--    existing package under a different existing parent (Prompt 237 §22's own "nest
--    containers" alt-flow, e.g. correcting a mis-nested carton before confirm) -- is a
--    real, dedicated `app.reparent_wms_package` RPC that performs a genuine, bounded
--    (`<= 100` levels, generously above any plausible real packing depth) ancestor walk
--    upward from the proposed new parent, rejecting (`cycle_rejected`) if the package
--    being moved is ever encountered in that walk (which would mean the package being
--    moved is already an ancestor of its own proposed new parent -- exactly a cycle).
--    Both a self-parent (`p_new_parent_package_id = p_package_id`) and a genuine
--    multi-level cycle are covered by this identical walk. Reparenting is only ever
--    permitted while BOTH the package being moved and its proposed new parent are
--    still `status = 'open'` (unconfirmed) -- a confirmed package's own hierarchy
--    position is immutable except via governed reopen (design note 5), consistent with
--    "confirmed package changes require governed reopen... not silent edit."
-- 3. **The aggregate lock for "how much of this pick task has already been packed"
--    (Prompt 237's own headline bug-class-(e) instance, this task brief's own explicit
--    instruction): `app.add_wms_package_line` locks the target `app.wms_pick_tasks`
--    row itself (`SELECT ... FOR UPDATE`) BEFORE computing `sum(quantity)` across that
--    task's own already-existing `app.wms_package_lines` rows (across ALL packages,
--    not merely the one being added to).** This exactly mirrors `app.generate_wms_
--    pick_task`'s own fix for "how much of an outbound order line has already been
--    allocated" (`ATW-017` design note 3) one level down the entity graph. The lock
--    order is deliberately PACKAGE-then-TASK (the target package is locked first, for
--    its own `status = 'open'`/version check, then the pick task): two concurrent
--    `add_wms_package_line` calls against the SAME task but TWO DIFFERENT packages
--    therefore never contend on the package lock at all (no shared row there) -- they
--    serialize PURELY on the task lock, which is the exact, isolated proof this
--    checkpoint's own required two-process concurrency test performs (mirrors `ATW-
--    017`'s own two-different-locations proof technique for the identical reason: to
--    prove the TASK lock specifically is what prevents joint over-commit, not
--    incidentally the narrower per-package lock).
-- 4. **Package identity/owner (Prompt 237 §33's own headline "no duplicate/wrong-owner
--    item can be packed" acceptance criterion): `owner_account_id` on `app.wms_
--    packages` is derived IMMUTABLY at creation from the packing task's own outbound
--    order (`app.wms_outbound_orders.owner_account_id`, itself immutable per `ATW-
--    016A`), never caller-supplied and never re-derived from "whichever line was added
--    first."** Every `app.add_wms_package_line` call independently re-validates BOTH
--    that the referenced pick task's own `outbound_order_id` matches the packing
--    task's own `outbound_order_id` (`wrong_order`) AND that the pick task's own
--    `owner_account_id` matches the package's own `owner_account_id` (`wrong_owner`) --
--    a deliberately redundant, defense-in-depth pair of checks: today a `wms_outbound_
--    orders` row is always genuinely single-owner (so the second check is currently
--    implied by the first), but asserting owner explicitly, not merely transitively,
--    means a future schema change that ever widens that invariant does not silently
--    reopen a wrong-owner leak here. Duplicate/over-pack is structurally the SAME
--    aggregate-lock guard as design note 3: `p_quantity` may never push the task's own
--    packed total past its own live `picked_quantity`.
-- 5. **"Confirmed package changes require governed reopen/repack with audit, not
--    silent edit" (Prompt 237 §24) is enforced BOTH at the RPC layer (every mutating
--    RPC below except `app.reopen_wms_package` itself hard-rejects `confirmed_package_
--    edit_rejected` once `status = 'confirmed'`) AND structurally, at the TABLE layer,
--    via five real CHECK constraints on `app.wms_packages` that make "confirmed with
--    an incomplete/inconsistent state" impossible to persist even if a future RPC bug
--    ever tried** (`wms_packages_confirm_requires_lines_check`, `..._requires_weight_
--    check`, `..._requires_qc_check`, `..._requires_seal_check`, `..._confirmed_shape_
--    check`) -- mirrors `app.wms_pick_tasks_claimed_shape_check`'s own "make the
--    invalid state unrepresentable" precedent (`ATW-017`) one level up. `app.reopen_
--    wms_package` is the ONLY path back from `confirmed`, is `OPS:Override`-gated
--    (supervisor-only, Prompt 237 §26's own "supervisors... reopen"), and resets QC/
--    seal (never the packed line contents themselves, preserving the real repack
--    starting point) -- forcing a genuine re-inspection/re-seal before the package may
--    be confirmed a second time, with a full before/after audit event captured via
--    `app.capture_audit_event` rather than a silent field update.
-- 6. **No claim/assignment concept on `app.wms_packages` (a disclosed, bounded design
--    choice, distinct from `ATW-014`/`ATW-017`'s own per-task claim workflow).** A
--    packing STATION is normally an open queue where several packers may work
--    different packages of the SAME outbound order concurrently -- unlike a single
--    pick/putaway task (one physical pick, one claimant), a package is a container
--    multiple lines/packers might reasonably touch in sequence during active packing.
--    Any actor holding `OPS:Edit` and real record/owner scope over the package may add/
--    remove lines, record measurements/QC/seal, or confirm it; concurrency safety comes
--    from the package row's own `SELECT ... FOR UPDATE` lock (design note 3), not from
--    a claimant identity check. Prompt 237 §26's own "assigned packers execute;
--    supervisors hold/reopen/approve exception" is satisfied by the `OPS:Edit`/`OPS:
--    Override` split itself (design note 5) -- "assigned" here means "holds packing
--    authority over this warehouse/owner scope," the identical resolution `ATW-015`'s
--    own `app.reserve_inventory`/`app.post_inventory_movement` already use for "who may
--    act," never a per-row claimed-by column this capability does not need.
-- 7. **QC is a real, bounded, package-level pass/fail/hold outcome (Prompt 237's own
--    disclosed bound), never a configurable checklist/rules engine.** `app.record_wms_
--    package_qc` records `qc_status`/`qc_reason`/`qc_by`/`qc_at`; a `fail`/`hold`
--    outcome structurally blocks `app.confirm_wms_package` (design note 5's own CHECK
--    constraint) unless a supervisor calls the separate, `OPS:Override`-gated `app.
--    override_wms_package_qc_hold`, which records its own distinct `qc_override_
--    reason`/`_by`/`_at` evidence trail rather than silently flipping `qc_status`
--    itself -- the original failed/held outcome remains visible and auditable even
--    after an override.
-- 8. **Six known bug classes, applied proactively (this session's established
--    taxonomy, ATW-013/014/016/016A/017; this is the sixth application):**
--    (a) every idempotent-replay short-circuit below runs strictly after authority/
--        tenant-scope confirmation, never before;
--    (b)/(c) `SELECT ... FOR UPDATE` on the first read of any row a mutation will
--        update, held through the final `UPDATE`/`INSERT`, `record_version` compared
--        only under that lock -- every packing-task/package/line mutation below;
--    (d) every create-once `(tenant_id, idempotency_key)` INSERT below (`app.
--        start_wms_packing_task`, `app.create_wms_package`, `app.add_wms_package_line`/
--        `app.remove_wms_package_line`'s own `app.wms_package_line_scans` evidence
--        insert, `app.confirm_wms_package`'s own `app.wms_package_confirmations`
--        evidence insert) is wrapped in a nested `begin/exception unique_violation`
--        recovery, re-selecting and returning the winner -- this migration composes no
--        already-applied function's own create-once insert (design note 0: no `app.
--        reserve_inventory`/`app.post_inventory_movement` call anywhere below), so
--        there is no second, composed layer to widen this time;
--    (e) the cross-row-aggregate double-pack race -- design note 3, this checkpoint's
--        own headline instance of the class, proved live via a real two-process psql
--        race (mirrors `scripts/db-tests/wms-picking-concurrency-helper.sh`'s own
--        technique, reused directly rather than re-derived);
--    (f) owner-account read scoping -- every read RPC below that returns packing-task/
--        package-specific data calls `app.actor_can_view_owner_scoped_row` (`ATW-016`)
--        IN ADDITION to tenant-wide `OPS:View`/warehouse-record-scope, and every `app.
--        can_access_record` call below (mutation and read alike) passes the row's own
--        real `owner_account_id` (as text) into `p_customer_account_ref`, never `null`.
--        Every RLS SELECT policy below reuses `app.wms_pick_record_scope_ok` (`ATW-
--        017`) directly rather than nesting a raw, non-SECURITY-DEFINER subquery
--        against `app.warehouses` a third time (the exact latent defect `ATW-017`'s own
--        review already found and fixed once).
-- 9. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--    ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Packing task numbering + header (design note 1).
create table app.wms_packing_task_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

create function app.next_wms_packing_task_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.wms_packing_task_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.wms_packing_task_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'WMSPACK-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

create table app.wms_packing_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  outbound_order_id uuid not null references app.wms_outbound_orders (id),
  owner_account_id uuid not null references app.accounts (id),
  packing_task_number text not null,
  idempotency_key text not null,
  created_by text,
  created_at timestamptz not null default now(),
  constraint wms_packing_tasks_number_unique unique (tenant_id, packing_task_number),
  constraint wms_packing_tasks_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_packing_tasks_one_per_order_unique unique (tenant_id, outbound_order_id)
);

comment on table app.wms_packing_tasks is
  'ATW-018: one lightweight, state-machine-free packing task per outbound order (design note 1) -- no status column; completion state is always derived from member app.wms_packages rows. unique (tenant_id, outbound_order_id) makes "one per order" a real, structural, race-safe guarantee, not merely a convention.';

create index wms_packing_tasks_tenant_warehouse_idx on app.wms_packing_tasks (tenant_id, warehouse_id);
create index wms_packing_tasks_tenant_owner_idx on app.wms_packing_tasks (tenant_id, owner_account_id);

-- 2. Packages -- self-referencing hierarchy (design note 2).
create table app.wms_package_number_counters (
  tenant_id uuid primary key references app.tenants (id),
  last_seq integer not null default 0
);

create function app.next_wms_package_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_seq integer;
begin
  insert into app.wms_package_number_counters (tenant_id, last_seq)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_seq = app.wms_package_number_counters.last_seq + 1
  returning last_seq into v_seq;

  return 'PKG-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 7, '0');
end;
$$;

create table app.wms_packages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  packing_task_id uuid not null references app.wms_packing_tasks (id),
  outbound_order_id uuid not null references app.wms_outbound_orders (id),
  owner_account_id uuid not null references app.accounts (id),
  parent_package_id uuid references app.wms_packages (id),
  package_number text not null,
  package_type text not null default 'carton',
  status text not null default 'open',
  weight_value numeric,
  weight_uom_code text references app.uoms (code),
  length_value numeric,
  width_value numeric,
  height_value numeric,
  dimension_uom_code text references app.uoms (code),
  material text,
  qc_status text not null default 'pending',
  qc_reason text,
  qc_by_auth_user_id uuid references auth.users (id),
  qc_by_label text,
  qc_at timestamptz,
  qc_override_reason text,
  qc_override_by_auth_user_id uuid references auth.users (id),
  qc_override_by_label text,
  qc_override_at timestamptz,
  seal_number text,
  sealed_by_auth_user_id uuid references auth.users (id),
  sealed_by_label text,
  sealed_at timestamptz,
  line_count integer not null default 0,
  total_packed_quantity numeric not null default 0,
  confirmed_at timestamptz,
  confirmed_by_auth_user_id uuid references auth.users (id),
  confirmed_by_label text,
  reopen_count integer not null default 0,
  reopened_at timestamptz,
  reopened_by_auth_user_id uuid references auth.users (id),
  reopened_by_label text,
  reopened_reason text,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_packages_number_unique unique (tenant_id, package_number),
  constraint wms_packages_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_packages_type_check check (package_type in ('carton', 'box', 'pallet', 'crate', 'container', 'envelope', 'other')),
  constraint wms_packages_status_check check (status in ('open', 'confirmed')),
  constraint wms_packages_qc_status_check check (qc_status in ('pending', 'pass', 'fail', 'hold')),
  constraint wms_packages_not_own_parent check (parent_package_id is distinct from id),
  constraint wms_packages_weight_positive_check check (weight_value is null or weight_value > 0),
  constraint wms_packages_length_positive_check check (length_value is null or length_value > 0),
  constraint wms_packages_width_positive_check check (width_value is null or width_value > 0),
  constraint wms_packages_height_positive_check check (height_value is null or height_value > 0),
  constraint wms_packages_line_count_check check (line_count >= 0),
  constraint wms_packages_total_packed_quantity_check check (total_packed_quantity >= 0),
  constraint wms_packages_qc_reason_check check (qc_status not in ('fail', 'hold') or (qc_reason is not null and length(trim(qc_reason)) > 0)),
  constraint wms_packages_qc_override_shape_check check (qc_override_at is null or (qc_override_reason is not null and length(trim(qc_override_reason)) > 0)),
  -- Design note 5: structural, table-level "confirmed implies complete" guarantees --
  -- defense in depth beneath the RPC-layer checks, mirrors app.wms_pick_tasks_claimed_
  -- shape_check's own "make the invalid state unrepresentable" precedent (ATW-017).
  constraint wms_packages_confirm_requires_lines_check check (status <> 'confirmed' or line_count > 0),
  constraint wms_packages_confirm_requires_weight_check check (status <> 'confirmed' or weight_value is not null),
  constraint wms_packages_confirm_requires_qc_check check (status <> 'confirmed' or qc_status = 'pass' or qc_override_at is not null),
  constraint wms_packages_confirm_requires_seal_check check (status <> 'confirmed' or parent_package_id is not null or seal_number is not null),
  constraint wms_packages_confirmed_shape_check check (
    (status = 'confirmed' and confirmed_at is not null and confirmed_by_auth_user_id is not null)
    or (status = 'open')
  )
);

comment on table app.wms_packages is
  'ATW-018: package/container hierarchy via a single self-referencing parent_package_id (design note 2), cycle-safe by construction at create time and by a real bounded ancestor walk at reparent time (app.reparent_wms_package). owner_account_id is immutable, derived from the packing task''s own outbound order at creation (design note 4), never caller-supplied. Five CHECK constraints make a "confirmed but incomplete" row unrepresentable (design note 5).';

create index wms_packages_packing_task_idx on app.wms_packages (packing_task_id);
create index wms_packages_outbound_order_idx on app.wms_packages (outbound_order_id);
create index wms_packages_parent_idx on app.wms_packages (parent_package_id);
create index wms_packages_tenant_owner_idx on app.wms_packages (tenant_id, owner_account_id);
create index wms_packages_tenant_warehouse_status_idx on app.wms_packages (tenant_id, warehouse_id, status);

create function app.touch_wms_packages_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_packages_touch_row
  before update on app.wms_packages
  for each row
  execute function app.touch_wms_packages_row();

-- 3. Package lines -- live, current contents. One row per (package, source pick task).
create table app.wms_package_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  package_id uuid not null references app.wms_packages (id),
  pick_task_id uuid not null references app.wms_pick_tasks (id),
  owner_account_id uuid not null references app.accounts (id),
  item_master_id uuid not null references app.item_masters (id),
  uom_code text not null references app.uoms (code),
  lot_number text,
  serial_number text,
  expiry_date date,
  quantity numeric not null,
  first_added_at timestamptz not null default now(),
  first_added_by_auth_user_id uuid references auth.users (id),
  first_added_by_label text,
  constraint wms_package_lines_package_task_unique unique (package_id, pick_task_id),
  constraint wms_package_lines_quantity_check check (quantity > 0)
);

comment on table app.wms_package_lines is
  'ATW-018: live current contents -- one row per (package, source pick task); quantity is the net currently-packed amount from that task into that package. Never the audit trail itself (see app.wms_package_line_scans for the append-only add/remove event evidence).';

create index wms_package_lines_package_idx on app.wms_package_lines (package_id);
create index wms_package_lines_pick_task_idx on app.wms_package_lines (pick_task_id);

-- 4. Package line scans -- append-only evidence, one row per real add/remove scan event.
create table app.wms_package_line_scans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  package_id uuid not null references app.wms_packages (id),
  pick_task_id uuid not null references app.wms_pick_tasks (id),
  event_type text not null,
  quantity numeric not null,
  scanned_item_master_id uuid references app.item_masters (id),
  scanned_lot_number text,
  scanned_serial_number text,
  reason text,
  idempotency_key text not null,
  actor_auth_user_id uuid references auth.users (id),
  actor_label text,
  occurred_at timestamptz not null default now(),
  constraint wms_package_line_scans_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_package_line_scans_event_type_check check (event_type in ('add', 'remove')),
  constraint wms_package_line_scans_quantity_check check (quantity > 0),
  constraint wms_package_line_scans_remove_reason_check check (event_type <> 'remove' or (reason is not null and length(trim(reason)) > 0))
);

comment on table app.wms_package_line_scans is
  'ATW-018: append-only evidence, one row per real (or idempotently replayed) add/remove-line event -- Prompt 237 section 18''s own "every add/remove scan" audit trail. Never updated or deleted by any grant in this migration.';

create index wms_package_line_scans_package_idx on app.wms_package_line_scans (package_id);
create index wms_package_line_scans_pick_task_idx on app.wms_package_line_scans (pick_task_id);

-- 5. Package confirmations -- append-only evidence, one row per real confirm event.
create table app.wms_package_confirmations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  package_id uuid not null references app.wms_packages (id),
  idempotency_key text not null,
  line_count_snapshot integer not null,
  total_quantity_snapshot numeric not null,
  confirmed_by_auth_user_id uuid references auth.users (id),
  confirmed_by_label text,
  confirmed_at timestamptz not null default now(),
  constraint wms_package_confirmations_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.wms_package_confirmations is
  'ATW-018: append-only confirm-event evidence, mirrors app.wms_pick_task_confirmations'' own shape one level up.';

create index wms_package_confirmations_package_idx on app.wms_package_confirmations (package_id);

-- 6. Mutations. Every mutation is RBAC-gated (OPS:Create/Edit/Override) and
-- record-scope-gated (app.can_access_record against the row's own warehouse's company
-- org unit AND owner_account_id, bug class f), and audited.

create function app.start_wms_packing_task(
  p_outbound_order_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packing_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_outbound_orders;
  v_warehouse app.warehouses;
  v_existing app.wms_packing_tasks;
  v_task app.wms_packing_tasks;
  v_number text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to start a packing task' using errcode = 'check_violation';
  end if;

  select * into v_order from app.wms_outbound_orders where id = p_outbound_order_id;
  if not found then
    raise exception 'outbound_order_not_found: %', p_outbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', v_order.warehouse_id, v_order.tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_order.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot start a packing task under warehouse %', p_actor_auth_user_id, v_order.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_packing_tasks where tenant_id = v_order.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;
  select * into v_existing from app.wms_packing_tasks where tenant_id = v_order.tenant_id and outbound_order_id = p_outbound_order_id;
  if found then
    return v_existing;
  end if;

  if v_order.status <> 'confirmed' then
    raise exception 'outbound_order_not_confirmed: % is % -- only confirmed outbound demand may be packed against', v_order.id, v_order.status using errcode = 'check_violation';
  end if;

  v_number := app.next_wms_packing_task_number(v_order.tenant_id);

  -- Bug class (d): a nested begin/exception unique_violation recovery -- either unique
  -- constraint (idempotency_key or the one-per-order guard) can fire under a genuine
  -- concurrent race; either way, re-select and return the real winner.
  begin
    insert into app.wms_packing_tasks (tenant_id, warehouse_id, outbound_order_id, owner_account_id, packing_task_number, idempotency_key, created_by)
    values (v_order.tenant_id, v_order.warehouse_id, v_order.id, v_order.owner_account_id, v_number, p_idempotency_key, p_actor_label)
    returning * into v_task;
  exception
    when unique_violation then
      select * into v_existing from app.wms_packing_tasks where tenant_id = v_order.tenant_id and outbound_order_id = p_outbound_order_id;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_wms_packing_task',
    'app.wms_packing_tasks', v_task.id, 'success', null, null, jsonb_build_object('outbound_order_id', p_outbound_order_id, 'packing_task_number', v_number)
  );

  return v_task;
end;
$$;

comment on function app.start_wms_packing_task is
  'ATW-018: idempotent on (tenant_id, idempotency_key), including under a genuine race (bug class d), AND on unique (tenant_id, outbound_order_id) -- one packing task per order, design note 1.';

create function app.create_wms_package(
  p_packing_task_id uuid,
  p_parent_package_id uuid,
  p_package_type text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_packing_task app.wms_packing_tasks;
  v_warehouse app.warehouses;
  v_parent app.wms_packages;
  v_existing app.wms_packages;
  v_package app.wms_packages;
  v_number text;
  v_type text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to create a package' using errcode = 'check_violation';
  end if;

  select * into v_packing_task from app.wms_packing_tasks where id = p_packing_task_id;
  if not found then
    raise exception 'packing_task_not_found: %', p_packing_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_packing_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_packing_task.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_packing_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_packing_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_packing_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot create a package under packing task %', p_actor_auth_user_id, p_packing_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing from app.wms_packages where tenant_id = v_packing_task.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  v_type := coalesce(p_package_type, 'carton');
  if v_type not in ('carton', 'box', 'pallet', 'crate', 'container', 'envelope', 'other') then
    raise exception 'invalid_package_type: % is not a recognized package type', v_type using errcode = 'check_violation';
  end if;

  if p_parent_package_id is not null then
    -- Design note 2a: cycle-safe by construction -- the new package''s own id does not
    -- exist yet, so this can only ever reference an already-existing, already-acyclic
    -- package.
    select * into v_parent from app.wms_packages where id = p_parent_package_id for update;
    if not found or v_parent.packing_task_id <> p_packing_task_id then
      raise exception 'parent_package_not_found: % is not a package of packing task %', p_parent_package_id, p_packing_task_id using errcode = 'no_data_found';
    end if;
    if v_parent.status = 'confirmed' then
      raise exception 'parent_package_confirmed: % has already been confirmed -- reopen it before nesting a new child under it', p_parent_package_id using errcode = 'check_violation';
    end if;
  end if;

  v_number := app.next_wms_package_number(v_packing_task.tenant_id);

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_packages (
      tenant_id, warehouse_id, packing_task_id, outbound_order_id, owner_account_id, parent_package_id,
      package_number, package_type, idempotency_key, created_by
    ) values (
      v_packing_task.tenant_id, v_packing_task.warehouse_id, p_packing_task_id, v_packing_task.outbound_order_id, v_packing_task.owner_account_id, p_parent_package_id,
      v_number, v_type, p_idempotency_key, p_actor_label
    )
    returning * into v_package;
  exception
    when unique_violation then
      select * into v_existing from app.wms_packages where tenant_id = v_packing_task.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_packing_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_wms_package',
    'app.wms_packages', v_package.id, 'success', null, null,
    jsonb_build_object('packing_task_id', p_packing_task_id, 'parent_package_id', p_parent_package_id, 'package_number', v_number, 'package_type', v_type)
  );

  return v_package;
end;
$$;

comment on function app.create_wms_package is
  'ATW-018: idempotent on (tenant_id, idempotency_key), including under a genuine race (bug class d). owner_account_id is always derived from the packing task''s own outbound order (design note 4), never caller-supplied.';

create function app.reparent_wms_package(
  p_package_id uuid,
  p_new_parent_package_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_new_parent app.wms_packages;
  v_walk app.wms_packages;
  v_depth integer := 0;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reparent package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;

  if p_new_parent_package_id is not null then
    if p_new_parent_package_id = p_package_id then
      raise exception 'cycle_rejected: package % cannot be its own parent', p_package_id using errcode = 'check_violation';
    end if;

    select * into v_new_parent from app.wms_packages where id = p_new_parent_package_id for update;
    if not found or v_new_parent.packing_task_id <> v_package.packing_task_id then
      raise exception 'parent_package_not_found: % is not a package of packing task %', p_new_parent_package_id, v_package.packing_task_id using errcode = 'no_data_found';
    end if;
    if v_new_parent.status = 'confirmed' then
      raise exception 'parent_package_confirmed: % has already been confirmed -- reopen it before nesting under it', p_new_parent_package_id using errcode = 'check_violation';
    end if;

    -- Design note 2b: a real, bounded ancestor walk upward from the proposed new
    -- parent -- if the package being moved is ever encountered, it is already an
    -- ancestor of its own proposed new parent, which is exactly a cycle.
    --
    -- Every node visited by the walk is locked FOR UPDATE (not just the moved
    -- package and its immediate new parent), matching the "row-locked from first
    -- read through final UPDATE" discipline this function already applies to
    -- p_package_id/p_new_parent_package_id above. Without this, two concurrent
    -- reparent calls whose locked row pairs are disjoint (e.g. reparent(A, new
    -- parent=D) and reparent(C, new parent=B), where each call's own ancestor
    -- walk only ever reads rows the other call hasn't locked) can each pass
    -- their own cycle check against pre-race state and both commit, together
    -- forming a real cycle -- reproduced live against two concurrent psql
    -- sessions prior to this fix. Locking every walked row instead means any
    -- such overlapping pair of concurrent reparents now contends on a real row
    -- lock somewhere in the two walks; Postgres's own deadlock detector aborts
    -- one of them (the caller sees a normal 'deadlock detected' error and can
    -- retry), and the survivor's walk always observes fully-committed state, so
    -- no cycle can ever be persisted.
    v_walk := v_new_parent;
    loop
      v_depth := v_depth + 1;
      if v_depth > 100 then
        raise exception 'cycle_rejected: package hierarchy exceeds the maximum supported depth (100) while checking for a cycle' using errcode = 'check_violation';
      end if;
      if v_walk.id = p_package_id then
        raise exception 'cycle_rejected: reparenting package % under % would create a cycle', p_package_id, p_new_parent_package_id using errcode = 'check_violation';
      end if;
      exit when v_walk.parent_package_id is null;
      select * into v_walk from app.wms_packages where id = v_walk.parent_package_id for update;
    end loop;
  end if;

  update app.wms_packages set parent_package_id = p_new_parent_package_id where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'reparent_wms_package',
    'app.wms_packages', v_package.id, 'success', null, null, jsonb_build_object('new_parent_package_id', p_new_parent_package_id)
  );

  return v_package;
end;
$$;

comment on function app.reparent_wms_package is
  'ATW-018: real, bounded (<=100 levels) ancestor-walk cycle rejection (design note 2b) -- the ONLY operation that could otherwise introduce a real cycle, since create-time nesting is cycle-safe by construction. Only ever permitted while both the package being moved and its proposed new parent are open (unconfirmed).';

create function app.add_wms_package_line(
  p_package_id uuid,
  p_pick_task_id uuid,
  p_quantity numeric,
  p_scanned_item_master_id uuid,
  p_scanned_lot_number text,
  p_scanned_serial_number text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_packing_task app.wms_packing_tasks;
  v_task app.wms_pick_tasks;
  v_existing_scan app.wms_package_line_scans;
  v_already_packed numeric;
  v_remaining_packable numeric;
  v_line app.wms_package_lines;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to add a package line' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  -- Package locked BEFORE the pick task (design note 3''s own deliberate lock order).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;
  select * into v_packing_task from app.wms_packing_tasks where id = v_package.packing_task_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot add a line to package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing_scan from app.wms_package_line_scans where tenant_id = v_package.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_package;
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: line quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  -- Design note 3 / bug class (e): the pick task row is locked FOR UPDATE from this
  -- point, held through the aggregate read and the line insert/update below --
  -- exactly mirroring app.generate_wms_pick_task''s own outbound-order-line lock.
  select * into v_task from app.wms_pick_tasks where id = p_pick_task_id for update;
  if not found or v_task.tenant_id <> v_package.tenant_id then
    raise exception 'task_not_found: %', p_pick_task_id using errcode = 'no_data_found';
  end if;

  -- Design note 4: wrong order / wrong owner -- defense-in-depth, both checked
  -- explicitly rather than relying on one implying the other.
  if v_task.outbound_order_id <> v_packing_task.outbound_order_id then
    raise exception 'wrong_order: pick task % belongs to outbound order %, not this package''s own outbound order %', p_pick_task_id, v_task.outbound_order_id, v_packing_task.outbound_order_id
      using errcode = 'check_violation';
  end if;
  if v_task.owner_account_id <> v_package.owner_account_id then
    raise exception 'wrong_owner: pick task % belongs to owner account %, not this package''s own owner account %', p_pick_task_id, v_task.owner_account_id, v_package.owner_account_id
      using errcode = 'check_violation';
  end if;

  if p_scanned_item_master_id is distinct from v_task.item_master_id then
    raise exception 'item_mismatch: scanned item % does not match pick task %''s own item %', p_scanned_item_master_id, p_pick_task_id, v_task.item_master_id using errcode = 'check_violation';
  end if;
  if v_task.lot_controlled and coalesce(p_scanned_lot_number, '') <> coalesce(v_task.lot_number, '') then
    if p_scanned_lot_number is null then
      raise exception 'missing_lot: pick task % is lot-controlled (lot %) -- a matching lot number is required', p_pick_task_id, v_task.lot_number using errcode = 'check_violation';
    end if;
    raise exception 'lot_mismatch: scanned lot % does not match pick task %''s own lot %', p_scanned_lot_number, p_pick_task_id, v_task.lot_number using errcode = 'check_violation';
  end if;
  if v_task.serial_controlled and coalesce(p_scanned_serial_number, '') <> coalesce(v_task.serial_number, '') then
    if p_scanned_serial_number is null then
      raise exception 'missing_serial: pick task % is serial-controlled (serial %) -- a matching serial number is required', p_pick_task_id, v_task.serial_number using errcode = 'check_violation';
    end if;
    raise exception 'serial_mismatch: scanned serial % does not match pick task %''s own serial %', p_scanned_serial_number, p_pick_task_id, v_task.serial_number using errcode = 'check_violation';
  end if;

  -- The headline aggregate, computed strictly under the task lock above (design note 3):
  -- how much of this task has already been packed, across ALL packages, not merely
  -- this one.
  select coalesce(sum(quantity), 0) into v_already_packed from app.wms_package_lines where pick_task_id = p_pick_task_id;
  v_remaining_packable := v_task.picked_quantity - v_already_packed;
  if p_quantity > v_remaining_packable then
    raise exception 'over_pack_rejected: % of % picked units remain unpacked for pick task %, requested %', v_remaining_packable, v_task.picked_quantity, p_pick_task_id, p_quantity
      using errcode = 'check_violation';
  end if;

  select * into v_line from app.wms_package_lines where package_id = p_package_id and pick_task_id = p_pick_task_id for update;
  if found then
    update app.wms_package_lines set quantity = quantity + p_quantity where id = v_line.id;
  else
    -- Bug class (d): a nested begin/exception unique_violation recovery.
    begin
      insert into app.wms_package_lines (
        tenant_id, package_id, pick_task_id, owner_account_id, item_master_id, uom_code, lot_number, serial_number, expiry_date, quantity, first_added_by_auth_user_id, first_added_by_label
      ) values (
        v_package.tenant_id, p_package_id, p_pick_task_id, v_task.owner_account_id, v_task.item_master_id, v_task.uom_code, v_task.lot_number, v_task.serial_number, v_task.expiry_date, p_quantity, p_actor_auth_user_id, p_actor_label
      );
    exception
      when unique_violation then
        update app.wms_package_lines set quantity = quantity + p_quantity where package_id = p_package_id and pick_task_id = p_pick_task_id;
    end;
  end if;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_package_line_scans (
      tenant_id, package_id, pick_task_id, event_type, quantity, scanned_item_master_id, scanned_lot_number, scanned_serial_number, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_package.tenant_id, p_package_id, p_pick_task_id, 'add', p_quantity, p_scanned_item_master_id, p_scanned_lot_number, p_scanned_serial_number, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent add-line request', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_packages set
    line_count = (select count(*) from app.wms_package_lines where package_id = p_package_id),
    total_packed_quantity = (select coalesce(sum(quantity), 0) from app.wms_package_lines where package_id = p_package_id)
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_wms_package_line',
    'app.wms_packages', v_package.id, 'success', null, null,
    jsonb_build_object('pick_task_id', p_pick_task_id, 'quantity', p_quantity)
  );

  return v_package;
end;
$$;

comment on function app.add_wms_package_line is
  'ATW-018: the headline bug-class-(e) fix -- locks the target pick task row (SELECT ... FOR UPDATE) before computing how much of it has already been packed, across ALL packages (design note 3). Lock order is package-then-task, so two concurrent calls against the SAME task but DIFFERENT packages serialize purely on the task lock. Rejects wrong_order/wrong_owner/item_mismatch/lot_mismatch/serial_mismatch/over_pack_rejected. Idempotent on (tenant_id, idempotency_key) via app.wms_package_line_scans.';

create function app.remove_wms_package_line(
  p_package_id uuid,
  p_pick_task_id uuid,
  p_quantity numeric,
  p_reason text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_existing_scan app.wms_package_line_scans;
  v_line app.wms_package_lines;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to remove a package line' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to remove a package line' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot remove a line from package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing_scan from app.wms_package_line_scans where tenant_id = v_package.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_package;
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: remove quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  select * into v_line from app.wms_package_lines where package_id = p_package_id and pick_task_id = p_pick_task_id for update;
  if not found then
    raise exception 'line_not_found: pick task % is not currently packed into package %', p_pick_task_id, p_package_id using errcode = 'no_data_found';
  end if;
  if p_quantity > v_line.quantity then
    raise exception 'exceeds_line_quantity: package % only has % of pick task % packed, cannot remove %', p_package_id, v_line.quantity, p_pick_task_id, p_quantity using errcode = 'check_violation';
  end if;

  if p_quantity = v_line.quantity then
    delete from app.wms_package_lines where id = v_line.id;
  else
    update app.wms_package_lines set quantity = quantity - p_quantity where id = v_line.id;
  end if;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_package_line_scans (
      tenant_id, package_id, pick_task_id, event_type, quantity, reason, idempotency_key, actor_auth_user_id, actor_label
    ) values (
      v_package.tenant_id, p_package_id, p_pick_task_id, 'remove', p_quantity, p_reason, p_idempotency_key, p_actor_auth_user_id, p_actor_label
    );
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent remove-line request', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_packages set
    line_count = (select count(*) from app.wms_package_lines where package_id = p_package_id),
    total_packed_quantity = (select coalesce(sum(quantity), 0) from app.wms_package_lines where package_id = p_package_id)
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'remove_wms_package_line',
    'app.wms_packages', v_package.id, 'success', p_reason, null,
    jsonb_build_object('pick_task_id', p_pick_task_id, 'quantity', p_quantity)
  );

  return v_package;
end;
$$;

comment on function app.remove_wms_package_line is
  'ATW-018: only ever callable pre-confirm (design note 5). Idempotent on (tenant_id, idempotency_key) via app.wms_package_line_scans; a real, non-empty reason is required for every removal.';

create function app.record_wms_package_measurements(
  p_package_id uuid,
  p_weight_value numeric,
  p_weight_uom_code text,
  p_length_value numeric,
  p_width_value numeric,
  p_height_value numeric,
  p_dimension_uom_code text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_before jsonb;
  v_weight_category text;
  v_dimension_category text;
  v_dims_provided integer;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot measure package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;

  if p_weight_value is null or p_weight_value <= 0 then
    raise exception 'invalid_weight: weight_value must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_weight_uom_code is null or not app.validate_uom_code(p_weight_uom_code) then
    raise exception 'invalid_uom: % is not a registered active UOM code', p_weight_uom_code using errcode = 'check_violation';
  end if;
  select unit_category into v_weight_category from app.uoms where code = p_weight_uom_code;
  if v_weight_category <> 'weight' then
    raise exception 'invalid_uom_category: % is a % UOM, weight is required for weight_uom_code', p_weight_uom_code, v_weight_category using errcode = 'check_violation';
  end if;

  v_dims_provided := (case when p_length_value is not null then 1 else 0 end)
    + (case when p_width_value is not null then 1 else 0 end)
    + (case when p_height_value is not null then 1 else 0 end);
  if v_dims_provided not in (0, 3) then
    raise exception 'invalid_dimensions: length/width/height must be supplied together or not at all' using errcode = 'check_violation';
  end if;
  if v_dims_provided = 3 then
    if p_length_value <= 0 or p_width_value <= 0 or p_height_value <= 0 then
      raise exception 'invalid_dimensions: length/width/height must each be greater than zero' using errcode = 'check_violation';
    end if;
    if p_dimension_uom_code is null or not app.validate_uom_code(p_dimension_uom_code) then
      raise exception 'invalid_uom: % is not a registered active UOM code', p_dimension_uom_code using errcode = 'check_violation';
    end if;
    select unit_category into v_dimension_category from app.uoms where code = p_dimension_uom_code;
    if v_dimension_category <> 'length' then
      raise exception 'invalid_uom_category: % is a % UOM, length is required for dimension_uom_code', p_dimension_uom_code, v_dimension_category using errcode = 'check_violation';
    end if;
  end if;

  v_before := jsonb_build_object(
    'weight_value', v_package.weight_value, 'weight_uom_code', v_package.weight_uom_code,
    'length_value', v_package.length_value, 'width_value', v_package.width_value, 'height_value', v_package.height_value, 'dimension_uom_code', v_package.dimension_uom_code
  );

  update app.wms_packages set
    weight_value = p_weight_value, weight_uom_code = p_weight_uom_code,
    length_value = p_length_value, width_value = p_width_value, height_value = p_height_value, dimension_uom_code = p_dimension_uom_code
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_package_measurements',
    'app.wms_packages', v_package.id, 'success', null, v_before,
    jsonb_build_object('weight_value', p_weight_value, 'weight_uom_code', p_weight_uom_code, 'length_value', p_length_value, 'width_value', p_width_value, 'height_value', p_height_value, 'dimension_uom_code', p_dimension_uom_code)
  );

  return v_package;
end;
$$;

comment on function app.record_wms_package_measurements is
  'ATW-018: weight is mandatory (weight_uom_code must be a weight-category UOM); length/width/height/dimension_uom_code are optional but must be supplied together (a dimension-category UOM) or not at all. Only ever callable pre-confirm.';

create function app.record_wms_package_qc(
  p_package_id uuid,
  p_qc_status text,
  p_qc_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot record QC on package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if p_qc_status not in ('pass', 'fail', 'hold') then
    raise exception 'invalid_qc_status: % is not a recognized QC outcome', p_qc_status using errcode = 'check_violation';
  end if;
  if p_qc_status in ('fail', 'hold') and (p_qc_reason is null or length(trim(p_qc_reason)) = 0) then
    raise exception 'invalid_reason: a non-empty reason is required for a % QC outcome', p_qc_status using errcode = 'check_violation';
  end if;

  -- A fresh QC event always supersedes any prior override (design note 7) -- the
  -- override applied to the PREVIOUS outcome, never automatically to a new one.
  update app.wms_packages set
    qc_status = p_qc_status, qc_reason = p_qc_reason, qc_by_auth_user_id = p_actor_auth_user_id, qc_by_label = p_actor_label, qc_at = now(),
    qc_override_reason = null, qc_override_by_auth_user_id = null, qc_override_by_label = null, qc_override_at = null
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_package_qc',
    'app.wms_packages', v_package.id, 'success', p_qc_reason, null, jsonb_build_object('qc_status', p_qc_status)
  );

  return v_package;
end;
$$;

comment on function app.record_wms_package_qc is
  'ATW-018: real, bounded pass/fail/hold outcome (design note 7), never a configurable checklist engine. fail/hold structurally blocks app.confirm_wms_package (table-level CHECK, design note 5) unless overridden via app.override_wms_package_qc_hold.';

create function app.override_wms_package_qc_hold(
  p_package_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot override QC on package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if v_package.qc_status not in ('fail', 'hold') then
    raise exception 'invalid_transition: package % QC status is % -- only a failed or held package may be overridden', p_package_id, v_package.qc_status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to override a QC hold' using errcode = 'check_violation';
  end if;

  update app.wms_packages set
    qc_override_reason = p_reason, qc_override_by_auth_user_id = p_actor_auth_user_id, qc_override_by_label = p_actor_label, qc_override_at = now()
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'override_wms_package_qc_hold',
    'app.wms_packages', v_package.id, 'success', p_reason, null, jsonb_build_object('overridden_qc_status', v_package.qc_status)
  );

  return v_package;
end;
$$;

comment on function app.override_wms_package_qc_hold is
  'ATW-018: OPS:Override-gated (supervisor-only, Prompt 237 section 26). Records a distinct, privileged qc_override_* evidence trail -- the original failed/held qc_status is never silently overwritten.';

create function app.record_wms_package_seal(
  p_package_id uuid,
  p_seal_number text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot seal package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'confirmed_package_edit_rejected: package % has already been confirmed -- use app.reopen_wms_package first', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;
  if p_seal_number is null or length(trim(p_seal_number)) = 0 then
    raise exception 'invalid_seal: a non-empty seal number is required' using errcode = 'check_violation';
  end if;

  update app.wms_packages set
    seal_number = p_seal_number, sealed_by_auth_user_id = p_actor_auth_user_id, sealed_by_label = p_actor_label, sealed_at = now()
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_package_seal',
    'app.wms_packages', v_package.id, 'success', null, null, jsonb_build_object('seal_number', p_seal_number)
  );

  return v_package;
end;
$$;

comment on function app.record_wms_package_seal is
  'ATW-018: only ever callable pre-confirm. app.confirm_wms_package requires a real seal_number for any ROOT package (parent_package_id is null) -- nested child containers are exempt (design note 5).';

create function app.confirm_wms_package(
  p_package_id uuid,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_existing_confirmation app.wms_package_confirmations;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to confirm a package' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot confirm package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before (bug class a).
  select * into v_existing_confirmation from app.wms_package_confirmations where tenant_id = v_package.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_package;
  end if;

  if v_package.status = 'confirmed' then
    raise exception 'package_already_confirmed: package % has already been confirmed', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;

  if v_package.line_count = 0 then
    raise exception 'empty_package_rejected: package % has no packed contents', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.weight_value is null then
    raise exception 'missing_measurement: package % has no recorded weight -- record measurements before confirming', p_package_id using errcode = 'check_violation';
  end if;
  if v_package.qc_status <> 'pass' and v_package.qc_override_at is null then
    if v_package.qc_status = 'pending' then
      raise exception 'missing_qc: package % has not yet been QC-inspected', p_package_id using errcode = 'check_violation';
    end if;
    raise exception 'qc_hold_unresolved: package % QC outcome is % -- resolve or override before confirming', p_package_id, v_package.qc_status using errcode = 'check_violation';
  end if;
  if v_package.parent_package_id is null and (v_package.seal_number is null or length(trim(v_package.seal_number)) = 0) then
    raise exception 'missing_seal: root package % has no recorded seal', p_package_id using errcode = 'check_violation';
  end if;

  -- Bug class (d): a nested begin/exception unique_violation recovery.
  begin
    insert into app.wms_package_confirmations (tenant_id, package_id, idempotency_key, line_count_snapshot, total_quantity_snapshot, confirmed_by_auth_user_id, confirmed_by_label)
    values (v_package.tenant_id, p_package_id, p_idempotency_key, v_package.line_count, v_package.total_packed_quantity, p_actor_auth_user_id, p_actor_label);
  exception
    when unique_violation then
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent confirm request', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.wms_packages set status = 'confirmed', confirmed_at = now(), confirmed_by_auth_user_id = p_actor_auth_user_id, confirmed_by_label = p_actor_label
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_wms_package',
    'app.wms_packages', v_package.id, 'success', null, null,
    jsonb_build_object('line_count', v_package.line_count, 'total_packed_quantity', v_package.total_packed_quantity)
  );

  return v_package;
end;
$$;

comment on function app.confirm_wms_package is
  'ATW-018: the "confirms once" step (Prompt 237 section 21). Rejects empty_package_rejected/missing_measurement/missing_qc/qc_hold_unresolved/missing_seal (root packages only). Idempotent on (tenant_id, idempotency_key) via app.wms_package_confirmations. Once confirmed, every other mutation in this migration except app.reopen_wms_package hard-rejects confirmed_package_edit_rejected.';

create function app.reopen_wms_package(
  p_package_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_packages
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
  v_before jsonb;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reopen a confirmed package' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final UPDATE -- bug class (b)/(c).
  select * into v_package from app.wms_packages where id = p_package_id for update;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reopen package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  if v_package.status <> 'confirmed' then
    raise exception 'not_confirmed: package % is % -- only a confirmed package may be reopened', p_package_id, v_package.status using errcode = 'check_violation';
  end if;
  if v_package.record_version <> p_expected_version then
    raise exception 'stale_version: package % expected version % but found %', p_package_id, p_expected_version, v_package.record_version using errcode = 'check_violation';
  end if;

  v_before := jsonb_build_object(
    'status', v_package.status, 'confirmed_at', v_package.confirmed_at, 'qc_status', v_package.qc_status, 'seal_number', v_package.seal_number
  );

  -- Design note 5: governed reopen -- resets QC/seal (forcing genuine re-inspection/
  -- re-seal before a second confirm), never the packed line contents themselves
  -- (design note 5's own "repack" preservation).
  update app.wms_packages set
    status = 'open',
    confirmed_at = null, confirmed_by_auth_user_id = null, confirmed_by_label = null,
    qc_status = 'pending', qc_reason = null, qc_by_auth_user_id = null, qc_by_label = null, qc_at = null,
    qc_override_reason = null, qc_override_by_auth_user_id = null, qc_override_by_label = null, qc_override_at = null,
    seal_number = null, sealed_by_auth_user_id = null, sealed_by_label = null, sealed_at = null,
    reopen_count = reopen_count + 1, reopened_at = now(), reopened_by_auth_user_id = p_actor_auth_user_id, reopened_by_label = p_actor_label, reopened_reason = p_reason
  where id = p_package_id
  returning * into v_package;

  perform app.capture_audit_event(
    v_package.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_wms_package',
    'app.wms_packages', v_package.id, 'success', p_reason, v_before, jsonb_build_object('status', v_package.status, 'reopen_count', v_package.reopen_count)
  );

  return v_package;
end;
$$;

comment on function app.reopen_wms_package is
  'ATW-018: OPS:Override-gated (supervisor-only). The ONLY path back from confirmed (design note 5) -- resets QC/seal, preserves packed line contents, records a full before/after audit event. A reopened package must satisfy every app.confirm_wms_package precondition again, including a fresh QC pass, before it may be confirmed a second time.';

-- 7. Reads. Owner-account scoping (bug class f) applied to every read below, IN
-- ADDITION to tenant-wide RBAC (OPS:View) and warehouse-record-scope.

create function app.get_wms_packing_task(p_packing_task_id uuid, p_actor_auth_user_id uuid)
returns app.wms_packing_tasks
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_packing_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_packing_tasks where id = p_packing_task_id;
  if not found then
    raise exception 'packing_task_not_found: %', p_packing_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_task.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view packing task %', p_actor_auth_user_id, p_packing_task_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_task.tenant_id, v_task.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view packing task %', p_actor_auth_user_id, p_packing_task_id using errcode = 'insufficient_privilege';
  end if;

  return v_task;
end;
$$;

comment on function app.get_wms_packing_task is
  'ATW-018: owner-account read scoping (bug class f) applied in addition to tenant-wide OPS:View and warehouse-record-scope.';

create function app.list_wms_packing_tasks(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_outbound_order_id uuid default null,
  p_limit integer default 50
)
returns setof app.wms_packing_tasks
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
  select t.* from app.wms_packing_tasks t
  join app.warehouses w on w.id = t.warehouse_id
  where t.tenant_id = p_tenant_id
    and (p_warehouse_id is null or t.warehouse_id = p_warehouse_id)
    and (p_outbound_order_id is null or t.outbound_order_id = p_outbound_order_id)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), t.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, t.owner_account_id)
  order by t.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_packing_tasks is
  'ATW-018: bounded read (p_limit default 50, hard-capped 200), record-scoped AND owner-account-scoped (bug class f).';

create function app.get_wms_package(p_package_id uuid, p_actor_auth_user_id uuid)
returns app.wms_packages
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_package app.wms_packages;
  v_warehouse app.warehouses;
begin
  select * into v_package from app.wms_packages where id = p_package_id;
  if not found then
    raise exception 'package_not_found: %', p_package_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_package.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_package.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_package.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_package.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), v_package.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_package.tenant_id, v_package.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view package %', p_actor_auth_user_id, p_package_id using errcode = 'insufficient_privilege';
  end if;

  return v_package;
end;
$$;

comment on function app.get_wms_package is
  'ATW-018: owner-account read scoping (bug class f) applied in addition to tenant-wide OPS:View and warehouse-record-scope.';

create function app.list_wms_package_lines(p_package_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_package_lines
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_package(p_package_id, p_actor_auth_user_id);
  return query select * from app.wms_package_lines where package_id = p_package_id order by first_added_at;
end;
$$;

comment on function app.list_wms_package_lines is
  'ATW-018: reuses app.get_wms_package for its own authority/record-scope/owner-scope gate rather than duplicating the checks.';

create function app.list_wms_package_line_scans(p_package_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_package_line_scans
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_package(p_package_id, p_actor_auth_user_id);
  return query select * from app.wms_package_line_scans where package_id = p_package_id order by occurred_at;
end;
$$;

create function app.list_wms_package_confirmations(p_package_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_package_confirmations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_package(p_package_id, p_actor_auth_user_id);
  return query select * from app.wms_package_confirmations where package_id = p_package_id order by confirmed_at;
end;
$$;

create function app.list_wms_packages(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_packing_task_id uuid default null,
  p_outbound_order_id uuid default null,
  p_owner_account_id uuid default null,
  p_parent_package_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.wms_packages
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
  select p.* from app.wms_packages p
  join app.warehouses w on w.id = p.warehouse_id
  where p.tenant_id = p_tenant_id
    and (p_packing_task_id is null or p.packing_task_id = p_packing_task_id)
    and (p_outbound_order_id is null or p.outbound_order_id = p_outbound_order_id)
    and (p_owner_account_id is null or p.owner_account_id = p_owner_account_id)
    and (p_parent_package_id is null or p.parent_package_id = p_parent_package_id)
    and (p_status_filter is null or p.status = p_status_filter)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), p.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, p.owner_account_id)
  order by p.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_packages is
  'ATW-018: bounded read (p_limit default 50, hard-capped 200), record-scoped per row by the package''s own warehouse company org unit AND owner-account-scoped (bug class f).';

-- 8. RLS -- record scope AND owner scope enforced in the database (bug class f), not
-- UI-only. Reuses app.wms_pick_record_scope_ok (ATW-017) directly rather than
-- re-deriving a raw, non-SECURITY-DEFINER subquery against app.warehouses a third time
-- (the exact latent defect ATW-017's own review already found and fixed once).

alter table app.wms_packing_tasks enable row level security;

create policy wms_packing_tasks_select_scoped on app.wms_packing_tasks
  for select to authenticated
  using (
    app.wms_pick_record_scope_ok(auth.uid(), wms_packing_tasks.warehouse_id, wms_packing_tasks.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(auth.uid(), wms_packing_tasks.tenant_id, wms_packing_tasks.owner_account_id)
  );

alter table app.wms_packages enable row level security;

create policy wms_packages_select_scoped on app.wms_packages
  for select to authenticated
  using (
    app.wms_pick_record_scope_ok(auth.uid(), wms_packages.warehouse_id, wms_packages.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(auth.uid(), wms_packages.tenant_id, wms_packages.owner_account_id)
  );

alter table app.wms_package_lines enable row level security;

create policy wms_package_lines_select_scoped on app.wms_package_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_packages p
      where p.id = wms_package_lines.package_id
        and app.wms_pick_record_scope_ok(auth.uid(), p.warehouse_id, p.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row(auth.uid(), p.tenant_id, p.owner_account_id)
    )
  );

alter table app.wms_package_line_scans enable row level security;

create policy wms_package_line_scans_select_scoped on app.wms_package_line_scans
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_packages p
      where p.id = wms_package_line_scans.package_id
        and app.wms_pick_record_scope_ok(auth.uid(), p.warehouse_id, p.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row(auth.uid(), p.tenant_id, p.owner_account_id)
    )
  );

alter table app.wms_package_confirmations enable row level security;

create policy wms_package_confirmations_select_scoped on app.wms_package_confirmations
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_packages p
      where p.id = wms_package_confirmations.package_id
        and app.wms_pick_record_scope_ok(auth.uid(), p.warehouse_id, p.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row(auth.uid(), p.tenant_id, p.owner_account_id)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.wms_packing_tasks, app.wms_packages, app.wms_package_lines, app.wms_package_line_scans, app.wms_package_confirmations to authenticated, service_role;
grant insert, update, delete on app.wms_packing_tasks, app.wms_packages, app.wms_package_lines, app.wms_package_line_scans, app.wms_package_confirmations to service_role;
grant insert, update on app.wms_packing_task_number_counters, app.wms_package_number_counters to service_role;

grant execute on function app.next_wms_packing_task_number(uuid) to service_role;
grant execute on function app.next_wms_package_number(uuid) to service_role;
grant execute on function app.start_wms_packing_task(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_wms_package(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.reparent_wms_package(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.add_wms_package_line(uuid, uuid, numeric, uuid, text, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.remove_wms_package_line(uuid, uuid, numeric, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.record_wms_package_measurements(uuid, numeric, text, numeric, numeric, numeric, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.record_wms_package_qc(uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.override_wms_package_qc_hold(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.record_wms_package_seal(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.confirm_wms_package(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_wms_package(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_packing_task(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_packing_tasks(uuid, uuid, uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.get_wms_package(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_package_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_package_line_scans(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_package_confirmations(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_packages(uuid, uuid, uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
