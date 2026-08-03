-- Advanced TMS/WMS capability ATW-013 (CG-S10-ATW-013, Prompt 232, "WMS Receiving" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). Implements this
-- prompt's own §4 objective: "server-acknowledged receiving that validates inbound
-- lines, captures actual quantity/condition and creates exact inventory ledger
-- movements into receiving/hold status."
--
-- Design boundary (disclosed):
--
-- 1. **A receipt session is a distinct header row, one non-cancelled session per
--    confirmed `app.wms_inbound_orders` row (a real partial unique index, not merely
--    an application check), with its own `in_progress`/`completed`/`cancelled`
--    lifecycle -- `app.wms_inbound_orders.status` itself is never widened.** Prompt
--    231's own bounded lifecycle (design note 8 there) stops at `confirmed`; this
--    migration tracks receiving progress entirely on `app.wms_receipt_sessions`
--    rather than editing the already-`VERIFIED` `wms_inbound_orders` CHECK
--    constraint -- a real, disclosed choice (the alternative, widening the inbound
--    order's own status enum, was considered and rejected: receiving is a distinct
--    physical-execution record with its own actor/evidence/QC shape, not one more
--    inbound-header status value). What this migration *does* discharge is the
--    obligation `ATW-012`'s own `app.cancel_wms_inbound` comment explicitly left open
--    ("ATW-232... is obligated to wire that guard"): `app.cancel_wms_inbound` is
--    `create or replace`-widened below (a new migration, the already-applied one is
--    never edited) to block cancelling an inbound order that already has an
--    active/completed receipt session.
-- 2. **A receipt line is auto-created 1:1 from every `app.wms_inbound_order_lines`
--    row the instant a session starts, snapshotting `item_master_id`/
--    `expected_uom_code`/`expected_quantity`/`lot_controlled`/`serial_controlled`/
--    `expiry_controlled`** -- the identical "governed snapshot at creation time, never
--    live re-derived" precedent `app.wms_inbound_order_lines` itself already
--    established over `app.item_masters` (ATW-012 design note 6). This also
--    structurally satisfies "validates inbound lines" (Prompt 232 §4): a receipt line
--    can never reference an item/UOM the inbound order itself did not already expect,
--    since it is never independently caller-supplied.
-- 3. **Over/short/damage/hold are columns, not states inferred from a single "actual
--    quantity" field (Prompt 232 §24: "explicit outcomes, never hidden quantity
--    edits").** `counted_quantity` is the total physically counted; `accepted_quantity`
--    + `damaged_quantity` + `held_quantity` + `rejected_quantity` must equal it exactly
--    (`wms_receipt_lines_equation_check`, Prompt 232 §25's own "actual accepted/
--    rejected/variance equation balances exactly"). `over_quantity`/`short_quantity`
--    are real `GENERATED ALWAYS` columns (`greatest(counted - expected, 0)` and its
--    mirror), never a value an RPC computes and can drift from the row's own base
--    columns.
-- 4. **Two distinct steps -- record, then commit -- not one combined call**, so a
--    supervisor can approve an overage (or a scan can be corrected) before anything
--    posts to the ledger. `app.record_wms_receipt_line_count` is a pure administrative
--    recording step (no ledger call, overwrite-not-add semantics -- a repeated
--    identical scan is structurally idempotent, Prompt 232 §17's own "repeated scans
--    idempotent," because the second call simply re-sets the same values rather than
--    accumulating a second count). `app.commit_wms_receipt_line` is the one and only
--    path that calls `app.post_inventory_movement` (ATW-015) -- accepted lands
--    `status='on_hand'`, damaged lands `status='damaged'`, held lands `status='held'`,
--    all at the session's own `receiving_location_id` (a `dock`/`staging` location,
--    never a final storage bin -- putaway is `ATW-233`'s own next task, out of scope
--    here per this session's own explicit scope decision). Rejected quantity posts no
--    movement at all -- refused goods never entered inventory. A line with
--    `over_quantity > 0` and no supervisor approval (`over_approved`) is rejected by
--    `app.commit_wms_receipt_line` with `unapproved_overage` (Prompt 232 §23) --
--    `app.approve_wms_receipt_overage` (a distinct `OPS:Override`-gated RPC, the
--    identical "manager/supervisor authority" action `app.override_route_planning_
--    selection`, ATW-224 Prompt 224 §26, and `app.record_transaction_lineage_override`
--    already established for this repository's own "supervisor approves a configured
--    exception" pattern -- reused, not a new authority level invented for this task)
--    is the one real approval gate; recording a fresh count on an already-approved
--    line resets `over_approved` to `false`, forcing re-approval rather than silently
--    carrying a stale sign-off forward onto a changed count.
-- 5. **`app.commit_wms_receipt_line` is idempotent by short-circuiting on
--    `status = 'committed'`, but only after the same OPS:Edit/tenant-scope authority
--    check every other mutation here runs first** -- an already-committed row must
--    never be readable by a caller with no grant on it, so authority is always
--    evaluated before the idempotent-replay short-circuit ever returns live data.
--    The caller may not know its own prior `p_expected_version` on a network-ambiguous
--    retry, so this function does not use `record_version` optimistic concurrency the
--    way every other mutation on this migration's own tables does (the same
--    convention `app.update_wms_inbound_order_line` already established) -- a
--    deliberate difference, not an inconsistency: this is a pure administrative
--    field update with no independent ledger-side idempotency key to fall back on for
--    every *other* mutation, but `app.commit_wms_receipt_line` and
--    `app.resolve_wms_receipt_hold` each instead row-lock (`SELECT ... FOR UPDATE`)
--    their own line on their very first read and hold that lock through
--    `app.post_inventory_movement` and the final status UPDATE -- two concurrent
--    calls on the same line (e.g. a client retry that regenerates a fresh
--    idempotency key after a slow/timed-out response) serialize on that lock rather
--    than both independently reading a pre-commit status and each posting their own
--    real ledger movement; the second caller only proceeds once the first has
--    committed, at which point it observes `status = 'committed'` and takes the
--    idempotent short-circuit instead of posting again.
-- 6. **A QC hold is resolved by a distinct, `OPS:Override`-gated RPC
--    (`app.resolve_wms_receipt_hold`) that posts a real two-line `adjustment`
--    movement (`held` -> `on_hand` or `held` -> `damaged`, same location) through
--    `app.post_inventory_movement` -- never a bare balance edit.** This resolves the
--    *disposition* of already-received, already-ledgered held stock (an explicit,
--    governed QC decision, Prompt 232 §26 "supervisor approves configured... QC") --
--    it never relocates the stock to a different location, which would be putaway
--    (`ATW-233`, explicitly out of scope this checkpoint). Idempotent the identical
--    way as `app.commit_wms_receipt_line` (short-circuits on `hold_resolved`, only
--    after authority is confirmed, under the identical `SELECT ... FOR UPDATE` lock
--    described in design note 5).
-- 7. **A receipt session may only be cancelled while `in_progress` and while zero of
--    its own lines have committed** (Prompt 232 §32: "do not delete confirmed
--    receipt; reverse through governed inventory movements"). Once any line has
--    posted a real ledger movement, the session can only move forward to
--    `completed` (accounting for every remaining line, including a fully-short line
--    recorded at zero) -- never silently abandoned mid-flight with stock already on
--    the books. `app.complete_wms_receipt_session` itself requires every one of the
--    session's own lines to be `committed` first (Prompt 232 §33: "confirmed
--    quantities and conditions reconcile exactly" -- no line may be left
--    unaccounted-for at completion).
-- 8. **UOM is exact, per Prompt 232 §24 ("use exact UOM").** A count may be entered in
--    any registered UOM (`p_uom_code`), but `app.record_wms_receipt_line_count`
--    converts every quantity (via `app.convert_uom_quantity`, ATW-011A) into the
--    line's own immutable `expected_uom_code` before storing or equation-checking it
--    -- every stored quantity on a `app.wms_receipt_lines` row is always in one
--    canonical UOM, never a mix.
-- 9. **A serial-controlled item is capped at `counted_quantity <= 1` per receipt
--    line** (`wms_receipt_lines_serial_cap_check`) -- a real, disclosed, bounded
--    design choice: this migration's own dimension model (like `app.inventory_
--    movement_lines` itself, ATW-015) carries exactly one `serial_number` per line,
--    so a serialized item needing multiple units requires multiple inbound-order
--    lines (one per serial), never a single line silently representing more than one
--    serialized unit. Duplicate-serial detection itself is not reinvented here --
--    `app.post_inventory_movement`'s own `serial_conflict` check (ATW-015) already
--    rejects a second unit of the same serial exceeding on-hand quantity 1, reused
--    verbatim at commit time.
-- 10. **Evidence/photo attachment reuses `app.files`' own generic polymorphic
--     `record_type`/`record_id` reference (PLT-128) directly**, `record_type =
--     'wms_receipt_line'` -- the identical "mechanism proven, live wiring deferred"
--     boundary `ATW-012`'s own design note 9 already used for the inbound order
--     itself. No dedicated evidence-requirement/completeness tracker is built here.
-- 11. **No REST/GraphQL surface, no scan-first PWA UI** -- this repository has
--     consistently deferred WMS UI/API surfaces at this checkpoint (`ATW-012`/`ATW-015`
--     §5 both disclose the identical boundary); Prompt 232 §15's PWA/scan UX and §14's
--     shared REST/GraphQL requirement are residual, disclosed scope, not silently
--     dropped. Customer-owner-scoped read projections (Prompt 232 §26 "customers see
--     only permitted receipt summary") are likewise deferred to whichever future
--     capability first builds `ATW-242` (Customer Inventory Access Contract), the
--     identical boundary `ATW-015`'s own design note 8 already disclosed.
-- 12. **"Assigned staff execute" (Prompt 232 §26) is enforced as `OPS:Create`/`OPS:Edit`
--     role authority plus warehouse record-scope (`app.can_access_record` against the
--     warehouse's own company org unit) -- the identical mechanism every other ATW-0XX
--     capability uses, not a new per-session user-assignment table.** No prior Phase 5
--     capability has ever built a literal "assigned user" grant/claim mechanism for a
--     task/session record; inventing one here, novel to this checkpoint, would be new-
--     feature authoring beyond what any prior capability established as this
--     repository's own real authorization primitive.
-- 13. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Receipt session header -- one non-cancelled session per confirmed inbound order.
create table app.wms_receipt_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  inbound_order_id uuid not null references app.wms_inbound_orders (id),
  receiving_location_id uuid not null references app.warehouse_locations (id),
  idempotency_key text not null,
  status text not null default 'in_progress',
  cancelled_reason text,
  started_by text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_receipt_sessions_status_check check (status in ('in_progress', 'completed', 'cancelled')),
  constraint wms_receipt_sessions_cancelled_reason_check check (status <> 'cancelled' or (cancelled_reason is not null and length(trim(cancelled_reason)) > 0)),
  constraint wms_receipt_sessions_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.wms_receipt_sessions is
  'ATW-013: one real receiving event against exactly one confirmed app.wms_inbound_orders row (design note 1) -- app.wms_inbound_orders.status is never widened. receiving_location_id must be a dock/staging location of the same warehouse (never a final storage bin -- putaway is ATW-233''s own scope).';

create unique index wms_receipt_sessions_inbound_order_unique on app.wms_receipt_sessions (tenant_id, inbound_order_id) where status <> 'cancelled';
create index wms_receipt_sessions_tenant_warehouse_status_idx on app.wms_receipt_sessions (tenant_id, warehouse_id, status);

create function app.touch_wms_receipt_sessions_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_receipt_sessions_touch_row
  before update on app.wms_receipt_sessions
  for each row
  execute function app.touch_wms_receipt_sessions_row();

-- 2. Receipt lines -- 1:1 with app.wms_inbound_order_lines at session-start time
-- (design note 2), carrying the full expected/counted/accepted/rejected/over/short/
-- damaged/held quantity dimension (design note 3).
create table app.wms_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  receipt_session_id uuid not null references app.wms_receipt_sessions (id),
  inbound_order_line_id uuid not null references app.wms_inbound_order_lines (id),
  line_number integer not null,
  item_master_id uuid not null references app.item_masters (id),
  owner_account_id uuid not null references app.accounts (id),
  expected_uom_code text not null references app.uoms (code),
  expected_quantity numeric not null,
  lot_controlled boolean not null default false,
  serial_controlled boolean not null default false,
  expiry_controlled boolean not null default false,
  counted_uom_code text references app.uoms (code),
  counted_quantity numeric not null default 0,
  accepted_quantity numeric not null default 0,
  damaged_quantity numeric not null default 0,
  held_quantity numeric not null default 0,
  rejected_quantity numeric not null default 0,
  over_quantity numeric generated always as (greatest(counted_quantity - expected_quantity, 0)) stored,
  short_quantity numeric generated always as (greatest(expected_quantity - counted_quantity, 0)) stored,
  lot_number text,
  serial_number text,
  expiry_date date,
  condition_notes text,
  status text not null default 'pending',
  over_approved boolean not null default false,
  over_approved_reason text,
  over_approved_by text,
  over_approved_at timestamptz,
  hold_resolved boolean not null default false,
  hold_resolution text,
  hold_resolved_reason text,
  hold_resolved_by text,
  hold_resolved_at timestamptz,
  resolution_movement_id uuid references app.inventory_movements (id),
  movement_id uuid references app.inventory_movements (id),
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_receipt_lines_session_line_unique unique (receipt_session_id, inbound_order_line_id),
  constraint wms_receipt_lines_status_check check (status in ('pending', 'counted', 'committed')),
  constraint wms_receipt_lines_quantity_nonneg_check check (
    counted_quantity >= 0 and accepted_quantity >= 0 and damaged_quantity >= 0 and held_quantity >= 0 and rejected_quantity >= 0
  ),
  constraint wms_receipt_lines_equation_check check (accepted_quantity + damaged_quantity + held_quantity + rejected_quantity = counted_quantity),
  constraint wms_receipt_lines_serial_cap_check check (not serial_controlled or counted_quantity <= 1),
  constraint wms_receipt_lines_over_approved_reason_check check (not over_approved or (over_approved_reason is not null and length(trim(over_approved_reason)) > 0)),
  constraint wms_receipt_lines_hold_resolution_check check (hold_resolution is null or hold_resolution in ('release_to_stock', 'confirm_damaged')),
  constraint wms_receipt_lines_hold_resolved_shape_check check (not hold_resolved or (hold_resolution is not null and hold_resolved_reason is not null and length(trim(hold_resolved_reason)) > 0))
);

comment on table app.wms_receipt_lines is
  'ATW-013: accepted_quantity + damaged_quantity + held_quantity + rejected_quantity must equal counted_quantity exactly (wms_receipt_lines_equation_check, Prompt 232 section 25). over_quantity/short_quantity are real GENERATED ALWAYS columns (design note 3), never independently caller-set. status: pending (auto-created, no count yet) -> counted (app.record_wms_receipt_line_count) -> committed (app.commit_wms_receipt_line, the one path that ever posts a real ledger movement via app.post_inventory_movement).';

create index wms_receipt_lines_session_idx on app.wms_receipt_lines (receipt_session_id);
create index wms_receipt_lines_tenant_item_idx on app.wms_receipt_lines (tenant_id, item_master_id);

create function app.touch_wms_receipt_lines_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_receipt_lines_touch_row
  before update on app.wms_receipt_lines
  for each row
  execute function app.touch_wms_receipt_lines_row();

-- 3. Mutations. Every mutation is RBAC-gated (OPS:Create/Edit/Override/View) and
-- record-scope-gated (app.can_access_record against the session's own warehouse's
-- company org unit), and audited.

create function app.start_wms_receipt_session(
  p_inbound_order_id uuid,
  p_receiving_location_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_receipt_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
  v_location app.warehouse_locations;
  v_existing app.wms_receipt_sessions;
  v_session app.wms_receipt_sessions;
  v_line app.wms_inbound_order_lines;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to start a receipt session' using errcode = 'check_violation';
  end if;

  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot start receiving under warehouse %', p_actor_auth_user_id, v_order.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select * into v_existing from app.wms_receipt_sessions where tenant_id = v_order.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select * into v_existing from app.wms_receipt_sessions where tenant_id = v_order.tenant_id and inbound_order_id = p_inbound_order_id and status <> 'cancelled';
  if found then
    return v_existing;
  end if;

  if v_order.status <> 'confirmed' then
    raise exception 'inbound_not_confirmed: % must be confirmed to start receiving, is %', p_inbound_order_id, v_order.status using errcode = 'check_violation';
  end if;

  select * into v_location from app.warehouse_locations where id = p_receiving_location_id;
  if not found then
    raise exception 'location_not_found: %', p_receiving_location_id using errcode = 'no_data_found';
  end if;
  if v_location.warehouse_id <> v_order.warehouse_id then
    raise exception 'incompatible_location: location % does not belong to warehouse %', p_receiving_location_id, v_order.warehouse_id using errcode = 'check_violation';
  end if;
  if v_location.location_type not in ('dock', 'staging') then
    raise exception 'incompatible_location: location % is a % -- receiving must land on a dock or staging location, not a final storage location', p_receiving_location_id, v_location.location_type
      using errcode = 'check_violation';
  end if;
  if v_location.status <> 'active' then
    raise exception 'incompatible_location: location % is not active', p_receiving_location_id using errcode = 'check_violation';
  end if;

  insert into app.wms_receipt_sessions (tenant_id, warehouse_id, inbound_order_id, receiving_location_id, idempotency_key, started_by)
  values (v_order.tenant_id, v_order.warehouse_id, p_inbound_order_id, p_receiving_location_id, p_idempotency_key, p_actor_label)
  returning * into v_session;

  for v_line in select * from app.wms_inbound_order_lines where inbound_order_id = p_inbound_order_id order by line_number loop
    insert into app.wms_receipt_lines (
      tenant_id, receipt_session_id, inbound_order_line_id, line_number, item_master_id, owner_account_id,
      expected_uom_code, expected_quantity, lot_controlled, serial_controlled, expiry_controlled
    ) values (
      v_order.tenant_id, v_session.id, v_line.id, v_line.line_number, v_line.item_master_id, v_order.owner_account_id,
      v_line.expected_uom_code, v_line.expected_quantity, v_line.lot_controlled, v_line.serial_controlled, v_line.expiry_controlled
    );
  end loop;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'start_wms_receipt_session',
    'app.wms_receipt_sessions', v_session.id, 'success', null, null,
    jsonb_build_object('inbound_order_id', p_inbound_order_id, 'receiving_location_id', p_receiving_location_id)
  );

  return v_session;
exception
  when unique_violation then
    -- Two callers racing the unlocked pre-insert existence checks above (same
    -- idempotency_key, or same non-cancelled inbound_order_id) both pass and race on
    -- the INSERT; the real partial unique indexes (wms_receipt_sessions_tenant_
    -- idempotency_unique, wms_receipt_sessions_inbound_order_unique) correctly let only
    -- one INSERT win. The loser re-selects and gracefully returns the winner's row --
    -- the same documented idempotency guarantee this function promises on the
    -- non-racing path -- rather than surfacing a raw, unclassified unique_violation
    -- (mirrors app.capture_lead's own unique_violation recovery, COM-143).
    select * into v_existing from app.wms_receipt_sessions where tenant_id = v_order.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      return v_existing;
    end if;
    select * into v_existing from app.wms_receipt_sessions where tenant_id = v_order.tenant_id and inbound_order_id = p_inbound_order_id and status <> 'cancelled';
    if found then
      return v_existing;
    end if;
    raise;
end;
$$;

comment on function app.start_wms_receipt_session is
  'ATW-013: idempotent on (tenant_id, idempotency_key) AND on (tenant_id, inbound_order_id) among non-cancelled sessions -- either a same-key or a same-order retry returns the identical session, never a second one, including under a genuine race on the unlocked pre-insert checks (the unique_violation handler re-selects rather than raising, mirrors app.capture_lead). Requires the inbound order to be confirmed and the receiving location to be an active dock/staging location of the same warehouse. Auto-creates one app.wms_receipt_lines row per app.wms_inbound_order_lines row.';

create function app.record_wms_receipt_line_count(
  p_line_id uuid,
  p_uom_code text,
  p_counted_quantity numeric,
  p_accepted_quantity numeric,
  p_damaged_quantity numeric,
  p_held_quantity numeric,
  p_rejected_quantity numeric,
  p_lot_number text,
  p_serial_number text,
  p_expiry_date date,
  p_condition_notes text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_receipt_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_uom_code text;
  v_counted numeric;
  v_accepted numeric;
  v_damaged numeric;
  v_held numeric;
  v_rejected numeric;
begin
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  if v_session.status <> 'in_progress' then
    raise exception 'session_not_in_progress: session % is % -- counts may only be recorded while in_progress', v_session.id, v_session.status using errcode = 'check_violation';
  end if;
  if v_line.status = 'committed' then
    raise exception 'line_already_committed: % has already been committed to inventory', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: receipt line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version using errcode = 'check_violation';
  end if;

  if p_counted_quantity is null or p_counted_quantity < 0
     or p_accepted_quantity is null or p_accepted_quantity < 0
     or p_damaged_quantity is null or p_damaged_quantity < 0
     or p_held_quantity is null or p_held_quantity < 0
     or p_rejected_quantity is null or p_rejected_quantity < 0 then
    raise exception 'invalid_quantity: counted/accepted/damaged/held/rejected quantities must all be non-negative' using errcode = 'check_violation';
  end if;

  v_uom_code := coalesce(p_uom_code, v_line.expected_uom_code);
  if not app.validate_uom_code(v_uom_code) then
    raise exception 'invalid_uom: % is not a registered active UOM code', v_uom_code using errcode = 'check_violation';
  end if;

  if v_uom_code = v_line.expected_uom_code then
    v_counted := p_counted_quantity;
    v_accepted := p_accepted_quantity;
    v_damaged := p_damaged_quantity;
    v_held := p_held_quantity;
    v_rejected := p_rejected_quantity;
  else
    v_counted := app.convert_uom_quantity(p_counted_quantity, v_uom_code, v_line.expected_uom_code);
    v_accepted := app.convert_uom_quantity(p_accepted_quantity, v_uom_code, v_line.expected_uom_code);
    v_damaged := app.convert_uom_quantity(p_damaged_quantity, v_uom_code, v_line.expected_uom_code);
    v_held := app.convert_uom_quantity(p_held_quantity, v_uom_code, v_line.expected_uom_code);
    v_rejected := app.convert_uom_quantity(p_rejected_quantity, v_uom_code, v_line.expected_uom_code);
  end if;

  if v_accepted + v_damaged + v_held + v_rejected <> v_counted then
    raise exception 'invalid_equation: accepted (%) + damaged (%) + held (%) + rejected (%) must equal counted (%)', v_accepted, v_damaged, v_held, v_rejected, v_counted
      using errcode = 'check_violation';
  end if;

  if v_line.lot_controlled and v_counted > 0 and (p_lot_number is null or length(trim(p_lot_number)) = 0) then
    raise exception 'missing_lot: item % is lot-controlled -- a lot number is required for a non-zero count', v_line.item_master_id using errcode = 'check_violation';
  end if;
  if v_line.expiry_controlled and v_counted > 0 and p_expiry_date is null then
    raise exception 'missing_expiry: item % is expiry-controlled -- an expiry date is required for a non-zero count', v_line.item_master_id using errcode = 'check_violation';
  end if;
  if v_line.serial_controlled and v_counted > 0 then
    if p_serial_number is null or length(trim(p_serial_number)) = 0 then
      raise exception 'missing_serial: item % is serial-controlled -- a serial number is required for a non-zero count', v_line.item_master_id using errcode = 'check_violation';
    end if;
    if v_counted > 1 then
      raise exception 'serial_quantity_exceeded: a single receipt line may record at most 1 unit of a serial-controlled item, got %', v_counted using errcode = 'check_violation';
    end if;
  end if;

  update app.wms_receipt_lines set
    counted_uom_code = v_uom_code,
    counted_quantity = v_counted,
    accepted_quantity = v_accepted,
    damaged_quantity = v_damaged,
    held_quantity = v_held,
    rejected_quantity = v_rejected,
    lot_number = p_lot_number,
    serial_number = p_serial_number,
    expiry_date = p_expiry_date,
    condition_notes = p_condition_notes,
    status = 'counted',
    over_approved = false,
    over_approved_reason = null,
    over_approved_by = null,
    over_approved_at = null
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_wms_receipt_line_count',
    'app.wms_receipt_lines', v_line.id, 'success', p_condition_notes, null,
    jsonb_build_object('counted_quantity', v_counted, 'accepted_quantity', v_accepted, 'damaged_quantity', v_damaged, 'held_quantity', v_held, 'rejected_quantity', v_rejected)
  );

  return v_line;
end;
$$;

comment on function app.record_wms_receipt_line_count is
  'ATW-013: pure administrative recording -- posts no ledger movement (design note 4). Overwrite, not accumulate, semantics -- a repeated identical call is structurally idempotent. Converts every quantity into the line''s own immutable expected_uom_code (design note 8) before storing or equation-checking it. Any successful call resets over_approved to false, forcing re-approval after a recount. Blocked once the line is committed or the session is no longer in_progress.';

create function app.approve_wms_receipt_overage(
  p_line_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_receipt_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
begin
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot approve overage on receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: receipt line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version using errcode = 'check_violation';
  end if;
  if v_line.status = 'committed' then
    raise exception 'line_already_committed: % has already been committed to inventory', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.over_quantity <= 0 then
    raise exception 'no_overage_to_approve: receipt line % has no overage (over_quantity=%)', p_line_id, v_line.over_quantity using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to approve an overage' using errcode = 'check_violation';
  end if;

  update app.wms_receipt_lines set
    over_approved = true, over_approved_reason = p_reason, over_approved_by = p_actor_label, over_approved_at = now()
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_wms_receipt_overage',
    'app.wms_receipt_lines', v_line.id, 'success', p_reason, null, jsonb_build_object('over_quantity', v_line.over_quantity)
  );

  return v_line;
end;
$$;

comment on function app.approve_wms_receipt_overage is
  'ATW-013: OPS:Override authority (Prompt 232 section 26 "supervisor approves configured discrepancy"), non-empty reason always required -- the real approval gate design note 4 names. The one path that lets app.commit_wms_receipt_line proceed on a line whose over_quantity > 0.';

create function app.commit_wms_receipt_line(
  p_line_id uuid,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_receipt_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_lines jsonb := '[]'::jsonb;
  v_movement app.inventory_movements;
begin
  -- Row-locked from this first read through commit/rollback (FOR UPDATE) so a second
  -- concurrent call on the same line -- e.g. a client retry that regenerates a fresh
  -- idempotency key after a slow/timed-out first response -- cannot read the
  -- pre-commit status, build its own movement lines, and call
  -- app.post_inventory_movement a second time before the first call's UPDATE has
  -- landed. The second caller instead blocks here until the first transaction
  -- commits, then observes status='committed' and takes the idempotent short-circuit
  -- below -- never a second real ledger movement for the same physical receipt.
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot commit receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is
  -- confirmed above, never before (an already-committed record must never be
  -- readable by a caller who could not otherwise access it).
  if v_line.status = 'committed' then
    return v_line;
  end if;

  if v_session.status <> 'in_progress' then
    raise exception 'session_not_in_progress: session % is % -- lines may only be committed while in_progress', v_session.id, v_session.status using errcode = 'check_violation';
  end if;
  if v_line.status <> 'counted' then
    raise exception 'line_not_counted: % must have a recorded count before it can be committed', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.record_version <> p_expected_version then
    raise exception 'stale_version: receipt line % expected version % but found %', p_line_id, p_expected_version, v_line.record_version using errcode = 'check_violation';
  end if;
  if v_line.over_quantity > 0 and not v_line.over_approved then
    raise exception 'unapproved_overage: receipt line % counted % over the expected % without supervisor approval', p_line_id, v_line.over_quantity, v_line.expected_quantity using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to commit a receipt line' using errcode = 'check_violation';
  end if;

  if v_line.accepted_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.accepted_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'on_hand'
    ));
  end if;
  if v_line.damaged_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.damaged_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'damaged'
    ));
  end if;
  if v_line.held_quantity > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
      'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.held_quantity,
      'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'held'
    ));
  end if;

  if jsonb_array_length(v_lines) > 0 then
    v_movement := app.post_inventory_movement(
      v_line.tenant_id, v_session.warehouse_id, 'receipt', 'wms_inbound_order', v_session.inbound_order_id, p_idempotency_key, v_line.condition_notes,
      v_lines, p_actor_auth_user_id, p_actor_label
    );
  end if;

  update app.wms_receipt_lines set status = 'committed', movement_id = v_movement.id
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'commit_wms_receipt_line',
    'app.wms_receipt_lines', v_line.id, 'success', null, null,
    jsonb_build_object('movement_id', v_movement.id, 'accepted_quantity', v_line.accepted_quantity, 'damaged_quantity', v_line.damaged_quantity, 'held_quantity', v_line.held_quantity)
  );

  return v_line;
end;
$$;

comment on function app.commit_wms_receipt_line is
  'ATW-013: row-locked (SELECT ... FOR UPDATE) on its very first read so a same-line retry under genuine concurrency cannot post app.post_inventory_movement twice (design note 5); idempotent by short-circuiting on status=committed, but only after OPS:Edit/tenant-scope authority is confirmed -- never before. The one and only path that ever calls app.post_inventory_movement for this line -- accepted/damaged/held each land at the session''s own receiving_location_id under status on_hand/damaged/held respectively; rejected_quantity posts nothing. Blocked by unapproved_overage when over_quantity > 0 and app.approve_wms_receipt_overage has not been called since the last count.';

create function app.complete_wms_receipt_session(
  p_session_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_receipt_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_uncommitted_count integer;
begin
  select * into v_session from app.wms_receipt_sessions where id = p_session_id for update;
  if not found then
    raise exception 'session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_session.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit receipt session %', p_actor_auth_user_id, p_session_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is
  -- confirmed above, never before (an already-completed session must never be
  -- readable by a caller who could not otherwise access it).
  if v_session.status = 'completed' then
    return v_session;
  end if;

  if v_session.record_version <> p_expected_version then
    raise exception 'stale_version: receipt session % expected version % but found %', p_session_id, p_expected_version, v_session.record_version using errcode = 'check_violation';
  end if;
  if v_session.status <> 'in_progress' then
    raise exception 'session_not_in_progress: % is % -- only an in_progress session may be completed', p_session_id, v_session.status using errcode = 'check_violation';
  end if;

  select count(*) into v_uncommitted_count from app.wms_receipt_lines where receipt_session_id = p_session_id and status <> 'committed';
  if v_uncommitted_count > 0 then
    raise exception 'lines_not_committed: % line(s) on session % are not yet committed', v_uncommitted_count, p_session_id using errcode = 'check_violation';
  end if;

  update app.wms_receipt_sessions set status = 'completed', completed_at = now() where id = p_session_id returning * into v_session;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'complete_wms_receipt_session',
    'app.wms_receipt_sessions', v_session.id, 'success', null, null, null
  );

  return v_session;
end;
$$;

comment on function app.complete_wms_receipt_session is
  'ATW-013: row-locked (SELECT ... FOR UPDATE) on its first read; idempotent no-op on an already-completed session, but only after OPS:Edit/tenant-scope authority is confirmed -- never before. Requires every one of the session''s own lines to be committed first (Prompt 232 section 33 "confirmed quantities and conditions reconcile exactly") -- a fully-short line must still be recorded (counted=0) and committed (a no-op movement) before completion, never silently left unaccounted-for.';

create function app.cancel_wms_receipt_session(
  p_session_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_receipt_sessions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_committed_count integer;
begin
  select * into v_session from app.wms_receipt_sessions where id = p_session_id for update;
  if not found then
    raise exception 'session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_session.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit receipt session %', p_actor_auth_user_id, p_session_id using errcode = 'insufficient_privilege';
  end if;

  if v_session.record_version <> p_expected_version then
    raise exception 'stale_version: receipt session % expected version % but found %', p_session_id, p_expected_version, v_session.record_version using errcode = 'check_violation';
  end if;
  if v_session.status = 'cancelled' then
    return v_session;
  end if;
  if v_session.status = 'completed' then
    raise exception 'session_not_in_progress: % is completed -- a completed receipt session may never be cancelled, only reversed through governed inventory movements', p_session_id using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a receipt session' using errcode = 'check_violation';
  end if;

  select count(*) into v_committed_count from app.wms_receipt_lines where receipt_session_id = p_session_id and status = 'committed';
  if v_committed_count > 0 then
    raise exception 'has_committed_lines: session % has % already-committed line(s) -- complete the session instead of cancelling once inventory has been posted', p_session_id, v_committed_count
      using errcode = 'check_violation';
  end if;

  update app.wms_receipt_sessions set status = 'cancelled', cancelled_reason = p_reason where id = p_session_id returning * into v_session;

  perform app.capture_audit_event(
    v_session.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_receipt_session',
    'app.wms_receipt_sessions', v_session.id, 'success', p_reason, null, null
  );

  return v_session;
end;
$$;

comment on function app.cancel_wms_receipt_session is
  'ATW-013: in_progress only, and only while zero of the session''s own lines have committed (design note 7, Prompt 232 section 32) -- once real inventory has posted, the session can only move forward to completed, never be cancelled.';

create function app.resolve_wms_receipt_hold(
  p_line_id uuid,
  p_resolution text,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_receipt_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_movement app.inventory_movements;
  v_target_status text;
begin
  -- Row-locked from this first read through commit/rollback (FOR UPDATE), the
  -- identical reasoning app.commit_wms_receipt_line''s own lock documents: a second
  -- concurrent call on the same line cannot read the pre-resolution state, build its
  -- own adjustment movement, and call app.post_inventory_movement a second time
  -- before the first call''s UPDATE has landed.
  select * into v_line from app.wms_receipt_lines where id = p_line_id for update;
  if not found then
    raise exception 'line_not_found: %', p_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot resolve a hold on receipt line %', p_actor_auth_user_id, p_line_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is
  -- confirmed above, never before (an already-resolved hold's disposition must never
  -- be readable by a caller who could not otherwise access it).
  if v_line.hold_resolved then
    return v_line;
  end if;

  if v_line.status <> 'committed' then
    raise exception 'line_not_committed: % must be committed to inventory before its held quantity may be resolved', p_line_id using errcode = 'check_violation';
  end if;
  if v_line.held_quantity <= 0 then
    raise exception 'no_held_quantity: receipt line % has no held quantity to resolve', p_line_id using errcode = 'check_violation';
  end if;
  if p_resolution not in ('release_to_stock', 'confirm_damaged') then
    raise exception 'invalid_resolution: % is not a recognized hold resolution', p_resolution using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to resolve a QC hold' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to resolve a QC hold' using errcode = 'check_violation';
  end if;

  v_target_status := case p_resolution when 'release_to_stock' then 'on_hand' else 'damaged' end;

  v_movement := app.post_inventory_movement(
    v_line.tenant_id, v_session.warehouse_id, 'adjustment', 'wms_inbound_order', v_session.inbound_order_id, p_idempotency_key, p_reason,
    jsonb_build_array(
      jsonb_build_object('owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
        'uom_code', v_line.expected_uom_code, 'signed_quantity', -v_line.held_quantity,
        'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', 'held'),
      jsonb_build_object('owner_account_id', v_line.owner_account_id, 'item_master_id', v_line.item_master_id, 'location_id', v_session.receiving_location_id,
        'uom_code', v_line.expected_uom_code, 'signed_quantity', v_line.held_quantity,
        'lot_number', v_line.lot_number, 'serial_number', v_line.serial_number, 'expiry_date', v_line.expiry_date, 'status', v_target_status)
    ),
    p_actor_auth_user_id, p_actor_label
  );

  update app.wms_receipt_lines set
    hold_resolved = true, hold_resolution = p_resolution, hold_resolved_reason = p_reason, hold_resolved_by = p_actor_label, hold_resolved_at = now(),
    resolution_movement_id = v_movement.id
  where id = p_line_id
  returning * into v_line;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_wms_receipt_hold',
    'app.wms_receipt_lines', v_line.id, 'success', p_reason, null, jsonb_build_object('resolution', p_resolution, 'movement_id', v_movement.id)
  );

  return v_line;
end;
$$;

comment on function app.resolve_wms_receipt_hold is
  'ATW-013: OPS:Override authority (design note 6, Prompt 232 section 26). Row-locked (SELECT ... FOR UPDATE) on its first read; idempotent by short-circuiting on hold_resolved (mirrors app.commit_wms_receipt_line), but only after authority/tenant-scope is confirmed -- never before. Posts a real two-line adjustment movement (held -> on_hand or held -> damaged, same location -- never a relocation, putaway is ATW-233''s own scope) through app.post_inventory_movement, never a bare balance edit.';

-- 4. Reads.

create function app.get_wms_receipt_session(p_session_id uuid, p_actor_auth_user_id uuid)
returns app.wms_receipt_sessions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
begin
  select * into v_session from app.wms_receipt_sessions where id = p_session_id;
  if not found then
    raise exception 'session_not_found: %', p_session_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_session.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_session.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_session.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view receipt session %', p_actor_auth_user_id, p_session_id using errcode = 'insufficient_privilege';
  end if;

  return v_session;
end;
$$;

create function app.list_wms_receipt_lines(p_session_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_receipt_lines
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_session app.wms_receipt_sessions;
begin
  v_session := app.get_wms_receipt_session(p_session_id, p_actor_auth_user_id);

  return query select * from app.wms_receipt_lines where receipt_session_id = p_session_id order by line_number;
end;
$$;

comment on function app.list_wms_receipt_lines is
  'ATW-013: reuses app.get_wms_receipt_session for its own authority/record-scope gate rather than duplicating the check.';

create function app.list_wms_receipt_sessions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_inbound_order_id uuid default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.wms_receipt_sessions
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
  select s.* from app.wms_receipt_sessions s
  join app.warehouses w on w.id = s.warehouse_id
  where s.tenant_id = p_tenant_id
    and (p_warehouse_id is null or s.warehouse_id = p_warehouse_id)
    and (p_inbound_order_id is null or s.inbound_order_id = p_inbound_order_id)
    and (p_status_filter is null or s.status = p_status_filter)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
  order by s.started_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_receipt_sessions is
  'ATW-013: bounded read (p_limit default 50, hard-capped 200), record-scoped per row by the session''s own warehouse company org unit.';

-- 5. Widen app.cancel_wms_inbound (already-applied migration 20260730180000, never
-- edited -- CREATE OR REPLACE in this new migration, mirroring 20260730170000's own
-- precedent) to discharge ATW-012's own disclosed obligation (design note 1): block
-- cancelling an inbound order that already has an active/completed receipt session.
create or replace function app.cancel_wms_inbound(
  p_inbound_order_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_inbound_orders
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_order app.wms_inbound_orders;
  v_warehouse app.warehouses;
begin
  select * into v_order from app.wms_inbound_orders where id = p_inbound_order_id;
  if not found then
    raise exception 'inbound_order_not_found: %', p_inbound_order_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_order.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_order.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_order.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_order.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit inbound order %', p_actor_auth_user_id, p_inbound_order_id using errcode = 'insufficient_privilege';
  end if;
  if v_order.record_version <> p_expected_version then
    raise exception 'stale_version: inbound order % expected version % but found %', p_inbound_order_id, p_expected_version, v_order.record_version
      using errcode = 'check_violation';
  end if;
  if v_order.status = 'cancelled' then
    return v_order;
  end if;

  if exists (select 1 from app.wms_receipt_sessions where inbound_order_id = p_inbound_order_id and status <> 'cancelled') then
    raise exception 'has_receipt_progress: inbound order % has an active or completed receipt session -- cancel or reconcile it first', p_inbound_order_id
      using errcode = 'check_violation';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel an inbound order' using errcode = 'check_violation';
  end if;

  update app.wms_inbound_orders set status = 'cancelled', cancelled_reason = p_reason where id = p_inbound_order_id returning * into v_order;

  perform app.capture_audit_event(
    v_order.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_inbound',
    'app.wms_inbound_orders', v_order.id, 'success', p_reason, null, null
  );

  return v_order;
end;
$$;

comment on function app.cancel_wms_inbound is
  'ATW-012/widened this checkpoint (ATW-013): discharges ATW-012''s own disclosed design note 8 obligation -- an inbound order with a real, active/completed app.wms_receipt_sessions row (design note 1) can no longer be cancelled.';

-- 6. RLS -- record scope enforced in the database (mirrors app.wms_inbound_orders),
-- not UI-only.

alter table app.wms_receipt_sessions enable row level security;

create policy wms_receipt_sessions_select_scoped on app.wms_receipt_sessions
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = wms_receipt_sessions.warehouse_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.wms_receipt_lines enable row level security;

create policy wms_receipt_lines_select_scoped on app.wms_receipt_lines
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_receipt_sessions s
      join app.warehouses w on w.id = s.warehouse_id
      where s.id = wms_receipt_lines.receipt_session_id
        and app.can_access_record(auth.uid(), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant -- re-applied even though this
-- migration also widens (not only creates) app.cancel_wms_inbound, the identical
-- precedent 20260730170000's own header already established.
revoke execute on all functions in schema app from public;

grant select on app.wms_receipt_sessions, app.wms_receipt_lines to authenticated, service_role;
grant insert, update, delete on app.wms_receipt_sessions, app.wms_receipt_lines to service_role;

grant execute on function app.start_wms_receipt_session(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.record_wms_receipt_line_count(uuid, text, numeric, numeric, numeric, numeric, numeric, text, text, date, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.approve_wms_receipt_overage(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.commit_wms_receipt_line(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.complete_wms_receipt_session(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_wms_receipt_session(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_wms_receipt_hold(uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_receipt_session(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_receipt_lines(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_receipt_sessions(uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.cancel_wms_inbound(uuid, text, integer, uuid, text) to authenticated, service_role;
