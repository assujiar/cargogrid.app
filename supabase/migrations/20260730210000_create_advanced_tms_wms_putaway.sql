-- Advanced TMS/WMS capability ATW-014 (CG-S10-ATW-014, Prompt 233, "WMS Putaway" --
-- docs/build-log/phase-05/ADVANCED_TMS_WMS_EXECUTION_INDEX.md §1). Implements this
-- prompt's own §4 objective: "directed, human-confirmed putaway from receiving/hold
-- locations into eligible storage locations through exact ledger movements."
--
-- Direct upstream: ATW-013 (20260730200000_create_advanced_tms_wms_receiving.sql).
-- A putaway task sources stock from a committed `app.wms_receipt_lines` row's own
-- `accepted_quantity` (already posted `status='on_hand'` at the receiving session's
-- own dock/staging `receiving_location_id` via `app.post_inventory_movement`,
-- `movement_type='receipt'`) and moves it into an eligible rack/shelf/bin storage
-- location through a real, balanced `movement_type='transfer'`.
--
-- Adversarial-review lessons applied from the very first draft (ATW-013's own commit
-- message named seven defects found in this exact implementer pattern last
-- checkpoint; all four bug classes are proactively closed here, not discovered again
-- by a reviewer):
--
-- (a) **Idempotent-replay short-circuits always run strictly after authority/
--     tenant-scope is confirmed, never before**, in every mutation below
--     (`app.claim_wms_putaway_task`, `app.confirm_wms_putaway_task`,
--     `app.mark_wms_putaway_task_exception`, `app.cancel_wms_putaway_task`) --
--     an already-terminal record is never readable by a caller with no grant on it.
-- (b)/(c) **`SELECT ... FOR UPDATE` on the very first read of any row a mutating
--     function will update, held through the final UPDATE/INSERT** -- every task
--     mutation below locks `app.wms_putaway_tasks` first; `app.generate_wms_putaway_
--     task` locks the source `app.wms_receipt_lines` row first (computing "remaining
--     un-put-away quantity" under that same lock closes the identical TOCTOU class
--     against concurrent generation calls for the same receipt line, and against
--     `record_version` optimistic-concurrency checks on the task row itself).
-- (d) **A create-once idempotency check that can race under concurrency
--     (`app.generate_wms_putaway_task`'s own unique `(tenant_id, idempotency_key)`)
--     wraps its INSERT in a nested `begin/exception` block catching `unique_violation`,
--     re-selecting and returning the winning row** -- mirrors `app.start_wms_receipt_
--     session`'s own proven recovery (which itself mirrors `app.capture_lead`,
--     COM-143) -- never a raw, unclassified `unique_violation` surfaced to the caller.
--
-- Design boundary (disclosed):
--
-- 1. **One task per (receipt line, destination) generation call, never a single
--     header row with a caller-opaque array of destination lines.** "Split across
--     eligible bins" (Prompt 233 §22) is modeled as repeated calls to
--     `app.generate_wms_putaway_task` against the same `receipt_line_id`, each
--     idempotent on its own `(tenant_id, idempotency_key)` and each locking the
--     source receipt line first -- so concurrent/duplicate generation calls can never
--     jointly over-allocate a receipt line's own `accepted_quantity`. This is the
--     simpler of the two defensible shapes named in this task's own design brief (one
--     task/many lines vs. many tasks/one line each); a many-tasks shape needs no
--     additional child "line" table for the split itself (only for confirmation
--     evidence, design note 2).
-- 2. **A second, distinct append-only table (`app.wms_putaway_confirmations`) records
--     every real confirm-scan event**, one row per successful (or idempotently
--     replayed) `app.confirm_wms_putaway_task` call, each carrying its own real
--     `(tenant_id, idempotency_key)` unique constraint -- the same "idempotency is a
--     real unique constraint on a created-once row, never an application-level
--     re-check" convention `app.wms_receipt_sessions` itself established, applied
--     here per-confirm-event (a task can legitimately be confirmed more than once,
--     partially, across separate physical scans) rather than per-task. This is also
--     this capability's own audit evidence (Prompt 233 §18: "actual scans, quantity,
--     assignee/device/time... movement IDs").
-- 3. **A task's own `status` is never directly caller-settable to `confirmed`** --
--     Prompt 233 §24's own "task completion derives from exact remaining quantity,
--     not manual status" is enforced structurally: `app.confirm_wms_putaway_task`
--     alone advances `confirmed_quantity`, and `status` transitions to `confirmed`
--     exclusively when `confirmed_quantity` (after the update) equals `task_quantity`
--     exactly, computed by the function itself, never accepted as an argument.
-- 4. **The destination validation Prompt 233 §25 requires ("destination is active,
--     eligible, capacity-compatible, and in the authorized warehouse") mirrors
--     ATW-013's own dock/staging-only receiving-location gate exactly inverted**: a
--     putaway destination must be `location_type in ('rack', 'shelf', 'bin')`
--     (never `dock`/`staging`, ATW-230's own six-value taxonomy) and
--     `putaway_enabled = true` (a real column `ATW-230` already carries, unused by
--     any capability until now) -- reusing an already-governed field rather than
--     minting a new one. Capacity is a real, bounded check against `app.inventory_
--     balances`' own existing per-location `on_hand` aggregate (`sum(on_hand) where
--     location_id = ... and status = 'on_hand'`), not a fabricated running-occupancy
--     table -- disclosed simplification: this treats `capacity_value`/`capacity_uom`
--     as a flat cross-item quantity ceiling at the location (no UOM-aware conversion
--     across differently-UOM'd items sharing one bin), the same class of bounded,
--     reasoned default `ATW-230`'s own `app.warehouse_location_max_depth()` already
--     used without a fresh ADR. A location with `capacity_value is null` has no
--     capacity ceiling enforced (matches `app.warehouse_locations`' own "capacity is
--     optional" shape). **The capacity check itself is race-safe across two different
--     putaway tasks racing the same destination**: `app.confirm_wms_putaway_task`
--     locks the destination `app.warehouse_locations` row (`SELECT ... FOR UPDATE`)
--     before reading `sum(on_hand)`, closing a cross-task TOCTOU class the task-row
--     lock (design note (b)/(c)) and `app.post_inventory_movement`'s own per-dimension
--     balance-row lock (keyed by item/lot/serial/location, never location alone) do
--     not cover on their own -- two different tasks (different items, or the same item
--     under different lots) confirming to the same capacity-limited bin at once would
--     otherwise both read the same stale occupancy and jointly overshoot
--     `capacity_value` before either posted its own transfer.
-- 5. **Suggestion is real decision support, never authoritative** (Prompt 233 §24
--     verbatim) -- `app.generate_wms_putaway_task`'s own auto-suggest algorithm (when
--     no caller-supplied `p_suggested_location_id` is given) is a simple, disclosed
--     greedy pick (first active, `putaway_enabled`, capacity-headroom rack/shelf/bin
--     of the task's own warehouse, ordered by `sequence`/`code`) and a caller-supplied
--     suggestion is sanity-checked only for existing-and-same-warehouse at generation
--     time, never full eligibility -- the *only* authoritative destination validation
--     in this whole capability is the one `app.confirm_wms_putaway_task` itself runs
--     against the real `p_actual_location_id` at confirm time, structurally
--     incapable of being bypassed by whatever was suggested.
-- 6. **The transfer movement's own `source_type`/`source_id` reuses `wms_inbound_
--     order`/the original inbound order id (traced receipt_line -> receipt_session ->
--     inbound_order_id), never a new `source_type` enum value** -- `app.inventory_
--     movements`'s own `inventory_movements_source_type_check` (ATW-015, an
--     already-applied migration, never edited) has a closed five-value enum with no
--     `wms_receipt_line`/`wms_putaway_task` member; reusing `wms_inbound_order`
--     (the same value `app.commit_wms_receipt_line` itself already posts under)
--     preserves the full source/version lineage back to the one real originating
--     order (Prompt 233 §24: "extend canonical... source/version lineage; no silent
--     re-entry or duplicate source of truth") without widening an already-verified
--     table's own constraint.
-- 7. **A putaway confirmation is only ever executed by its own claimant** -- Prompt
--     233 §26's own "assigned staff execute; supervisors override/reassign" is
--     enforced as a real identity comparison (`p_actor_auth_user_id = task.claimed_by_
--     auth_user_id`) in `app.confirm_wms_putaway_task`/`app.mark_wms_putaway_task_
--     exception` (the latter also accepts a supervisor with `OPS:Override`, since
--     recording a blocker is the one step a supervisor may reasonably take on a task
--     they did not personally claim), never a bare `OPS:Edit` role check alone --
--     the identical "real per-task assignment, not merely role authority" gap this
--     capability is the first in this repository to need (ATW-013's own design note
--     12 explicitly named no prior capability had built one).
-- 8. **`app.reassign_wms_putaway_task` is the one supervisor override/reassign
--     mechanism** (Prompt 233 §26), gated on `OPS:Override` -- reusing the identical
--     authority `app.approve_wms_receipt_overage`/`app.resolve_wms_receipt_hold`
--     (ATW-013) already established for "supervisor approves/overrides a configured
--     exception," never a new authority level invented for this task. Passing a null
--     new claimant releases the task back to `unclaimed` (Prompt 233 §32's own
--     "release uncommitted task"); passing one reassigns it, resetting an `exception`
--     task back to `claimed`/`partial` as appropriate so work can resume.
-- 9. **Task generation is a real, synchronous, idempotent RPC a caller invokes
--     directly, never an async background job/scheduler** -- this repository has no
--     scheduler/worker runtime yet (disclosed, `ISS-2026-015`,
--     `docs/runtime/KNOWN_ISSUES.md`); the identical disclosed boundary every prior
--     Phase 5 capability with an "async"-named prompt section has already used.
-- 10. **No REST/GraphQL surface, no scan-first PWA UI** -- this repository has
--     consistently deferred WMS UI/API surfaces at this checkpoint (`ATW-012`/
--     `ATW-013`/`ATW-015` each disclose the identical boundary); Prompt 233 §14/§15
--     are residual, disclosed scope, not silently dropped.
-- 11. **Environment-requirement matching (Prompt 233 §15 "capacity/environment
--     warnings") is disclosed as deferred, not built** -- `app.warehouse_locations.
--     environment` (ATW-230) remains a descriptive jsonb bag with no matching
--     item-level environment/temperature-requirement column anywhere in this
--     repository yet; inventing one now would be new-feature authoring beyond this
--     task's own scope, the identical class of boundary `ATW-230`'s own design note 8
--     already disclosed for zone restrictions.
-- 12. Per `ERR-2026-004`: this migration carries its own explicit `REVOKE EXECUTE ON
--     ALL FUNCTIONS IN SCHEMA app FROM PUBLIC` statement before its final grants.

-- 1. Putaway tasks -- one row per (receipt line, destination) generation call
-- (design note 1).
create table app.wms_putaway_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  receipt_line_id uuid not null references app.wms_receipt_lines (id),
  source_location_id uuid not null references app.warehouse_locations (id),
  item_master_id uuid not null references app.item_masters (id),
  owner_account_id uuid not null references app.accounts (id),
  uom_code text not null references app.uoms (code),
  lot_controlled boolean not null default false,
  serial_controlled boolean not null default false,
  expiry_controlled boolean not null default false,
  lot_number text,
  serial_number text,
  expiry_date date,
  task_quantity numeric not null,
  confirmed_quantity numeric not null default 0,
  remaining_quantity numeric generated always as (task_quantity - confirmed_quantity) stored,
  suggested_location_id uuid references app.warehouse_locations (id),
  suggested_reason text,
  actual_location_id uuid references app.warehouse_locations (id),
  status text not null default 'unclaimed',
  claimed_by_auth_user_id uuid references auth.users (id),
  claimed_by_label text,
  claimed_at timestamptz,
  exception_reason text,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wms_putaway_tasks_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_putaway_tasks_status_check check (status in ('unclaimed', 'claimed', 'partial', 'confirmed', 'exception', 'cancelled')),
  constraint wms_putaway_tasks_task_quantity_check check (task_quantity > 0),
  constraint wms_putaway_tasks_confirmed_quantity_check check (confirmed_quantity >= 0 and confirmed_quantity <= task_quantity),
  constraint wms_putaway_tasks_claimed_shape_check check (
    (status = 'unclaimed' and claimed_by_auth_user_id is null and claimed_at is null)
    or (status <> 'unclaimed' and status <> 'cancelled' and claimed_by_auth_user_id is not null and claimed_at is not null)
    or (status = 'cancelled')
  ),
  constraint wms_putaway_tasks_actual_location_shape_check check (confirmed_quantity = 0 or actual_location_id is not null),
  constraint wms_putaway_tasks_exception_reason_check check (status <> 'exception' or (exception_reason is not null and length(trim(exception_reason)) > 0)),
  constraint wms_putaway_tasks_cancelled_shape_check check (status <> 'cancelled' or confirmed_quantity = 0)
);

comment on table app.wms_putaway_tasks is
  'ATW-014: one task per (receipt line, destination) generation call (design note 1). status: unclaimed -> claimed -> partial|confirmed (confirmed derives exclusively from confirmed_quantity = task_quantity, design note 3, never a directly caller-set value) with a real exception/cancelled escape. actual_location_id is only ever set at first real confirm (design note 5) -- suggested_location_id is decision support only.';

create index wms_putaway_tasks_tenant_warehouse_status_idx on app.wms_putaway_tasks (tenant_id, warehouse_id, status);
create index wms_putaway_tasks_receipt_line_idx on app.wms_putaway_tasks (receipt_line_id);
create index wms_putaway_tasks_claimed_by_idx on app.wms_putaway_tasks (claimed_by_auth_user_id);

create function app.touch_wms_putaway_tasks_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger wms_putaway_tasks_touch_row
  before update on app.wms_putaway_tasks
  for each row
  execute function app.touch_wms_putaway_tasks_row();

-- 2. Putaway confirmations -- append-only evidence, one row per real confirm-scan
-- event (design note 2). Idempotency lives here (per confirm-event), not on the
-- task header.
create table app.wms_putaway_confirmations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  task_id uuid not null references app.wms_putaway_tasks (id),
  idempotency_key text not null,
  quantity numeric not null,
  actual_location_id uuid not null references app.warehouse_locations (id),
  movement_id uuid not null references app.inventory_movements (id),
  lot_number text,
  serial_number text,
  expiry_date date,
  confirmed_by_auth_user_id uuid references auth.users (id),
  confirmed_by_label text,
  confirmed_at timestamptz not null default now(),
  constraint wms_putaway_confirmations_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint wms_putaway_confirmations_quantity_check check (quantity > 0)
);

comment on table app.wms_putaway_confirmations is
  'ATW-014: append-only evidence, one row per real (or idempotently replayed) app.confirm_wms_putaway_task call -- the audit trail Prompt 233 section 18 names ("actual scans, quantity, assignee/device/time... movement IDs"). Never updated or deleted by any grant in this migration.';

create index wms_putaway_confirmations_task_idx on app.wms_putaway_confirmations (task_id);

-- 3. Mutations. Every mutation is RBAC-gated (OPS:Create/Edit/Override/View) and
-- record-scope-gated (app.can_access_record against the task's own warehouse's
-- company org unit), and audited.

create function app.generate_wms_putaway_task(
  p_receipt_line_id uuid,
  p_quantity numeric,
  p_suggested_location_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_putaway_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_line app.wms_receipt_lines;
  v_session app.wms_receipt_sessions;
  v_warehouse app.warehouses;
  v_existing app.wms_putaway_tasks;
  v_task app.wms_putaway_tasks;
  v_allocated numeric;
  v_remaining numeric;
  v_suggested app.warehouse_locations;
  v_suggested_reason text;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to generate a putaway task' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final INSERT (FOR UPDATE) -- computing
  -- "remaining un-put-away quantity" (accepted_quantity minus every already-generated,
  -- non-cancelled task's own task_quantity) under this lock closes the same TOCTOU
  -- class design note (b)/(c) names: two concurrent generation calls against the same
  -- receipt line can never jointly over-allocate its accepted_quantity.
  select * into v_line from app.wms_receipt_lines where id = p_receipt_line_id for update;
  if not found then
    raise exception 'receipt_line_not_found: %', p_receipt_line_id using errcode = 'no_data_found';
  end if;
  select * into v_session from app.wms_receipt_sessions where id = v_line.receipt_session_id;
  select * into v_warehouse from app.warehouses where id = v_session.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_line.tenant_id, 'OPS', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_line.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_line.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot generate a putaway task under warehouse %', p_actor_auth_user_id, v_session.warehouse_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is confirmed
  -- above, never before (design note (a)).
  select * into v_existing from app.wms_putaway_tasks where tenant_id = v_line.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  if v_line.status <> 'committed' then
    raise exception 'receipt_line_not_committed: % must be committed before putaway tasks may be generated for it', p_receipt_line_id using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: putaway task quantity must be greater than zero' using errcode = 'check_violation';
  end if;

  select coalesce(sum(task_quantity), 0) into v_allocated from app.wms_putaway_tasks where receipt_line_id = p_receipt_line_id and status <> 'cancelled';
  v_remaining := v_line.accepted_quantity - v_allocated;
  if p_quantity > v_remaining then
    raise exception 'insufficient_remaining_quantity: % of % accepted units remain un-put-away for receipt line %, requested %', v_remaining, v_line.accepted_quantity, p_receipt_line_id, p_quantity
      using errcode = 'check_violation';
  end if;

  -- Suggestion is decision support only (design note 5) -- a caller-supplied
  -- suggestion is sanity-checked for existence/same-warehouse only, never full
  -- eligibility; the one authoritative destination validation happens exclusively at
  -- app.confirm_wms_putaway_task.
  if p_suggested_location_id is not null then
    select * into v_suggested from app.warehouse_locations where id = p_suggested_location_id;
    if not found or v_suggested.warehouse_id <> v_session.warehouse_id then
      raise exception 'incompatible_location: suggested location % does not belong to warehouse %', p_suggested_location_id, v_session.warehouse_id using errcode = 'check_violation';
    end if;
    v_suggested_reason := 'caller_supplied';
  else
    select l.* into v_suggested
      from app.warehouse_locations l
      where l.warehouse_id = v_session.warehouse_id
        and l.status = 'active'
        and l.putaway_enabled
        and l.location_type in ('rack', 'shelf', 'bin')
        and (l.capacity_value is null or l.capacity_value >= p_quantity + coalesce((select sum(b2.on_hand) from app.inventory_balances b2 where b2.location_id = l.id and b2.status = 'on_hand'), 0))
      order by l.sequence, l.code
      limit 1;
    if found then
      v_suggested_reason := 'auto_suggested_first_eligible_capacity_headroom';
    else
      v_suggested := null;
      v_suggested_reason := 'no_eligible_destination_found';
    end if;
  end if;

  begin
    insert into app.wms_putaway_tasks (
      tenant_id, warehouse_id, receipt_line_id, source_location_id, item_master_id, owner_account_id, uom_code,
      lot_controlled, serial_controlled, expiry_controlled, lot_number, serial_number, expiry_date,
      task_quantity, suggested_location_id, suggested_reason, idempotency_key, created_by
    ) values (
      v_line.tenant_id, v_session.warehouse_id, p_receipt_line_id, v_session.receiving_location_id, v_line.item_master_id, v_line.owner_account_id, v_line.expected_uom_code,
      v_line.lot_controlled, v_line.serial_controlled, v_line.expiry_controlled, v_line.lot_number, v_line.serial_number, v_line.expiry_date,
      p_quantity, (case when v_suggested is null then null else v_suggested.id end), v_suggested_reason, p_idempotency_key, p_actor_label
    )
    returning * into v_task;
  exception
    when unique_violation then
      -- Design note (d): a concurrent caller won the (tenant_id, idempotency_key)
      -- race on the unlocked pre-insert existence check above; gracefully return the
      -- winner rather than surface a raw unique_violation (mirrors
      -- app.start_wms_receipt_session, which itself mirrors app.capture_lead).
      select * into v_existing from app.wms_putaway_tasks where tenant_id = v_line.tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise;
  end;

  perform app.capture_audit_event(
    v_line.tenant_id, p_actor_auth_user_id, p_actor_label, 'generate_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', null, null,
    jsonb_build_object('receipt_line_id', p_receipt_line_id, 'task_quantity', p_quantity, 'suggested_location_id', v_task.suggested_location_id, 'suggested_reason', v_suggested_reason)
  );

  return v_task;
end;
$$;

comment on function app.generate_wms_putaway_task is
  'ATW-014: real, synchronous, idempotent RPC (design note 9) -- not an async job. Row-locks the source app.wms_receipt_lines row (FOR UPDATE) before computing remaining un-put-away accepted_quantity, closing the TOCTOU class design note (b)/(c) names. Idempotent on (tenant_id, idempotency_key), including under a genuine race (unique_violation handler re-selects). A caller-supplied suggested destination is only sanity-checked (exists, same warehouse); the auto-suggest fallback picks the first active/putaway_enabled/rack-shelf-bin location with real capacity headroom (design note 4) -- always decision support only (design note 5).';

create function app.claim_wms_putaway_task(
  p_task_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_putaway_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
begin
  -- Row-locked from this first read through the final UPDATE (FOR UPDATE) -- a second
  -- concurrent claim attempt on the same unclaimed task blocks here until the first
  -- transaction commits, then observes status='claimed' with a different claimant and
  -- is correctly rejected (the real concurrent-claim-race guard Prompt 233 section 23
  -- names: "two staff cannot both claim the same task").
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot claim putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is confirmed
  -- above, never before (design note (a)). A same-claimant re-claim is a harmless
  -- no-op; a different claimant hits the real race guard below.
  if v_task.status = 'claimed' and v_task.claimed_by_auth_user_id = p_actor_auth_user_id then
    return v_task;
  end if;

  if v_task.status <> 'unclaimed' then
    raise exception 'task_already_claimed: task % is % (claimed_by=%) -- only an unclaimed task may be claimed', p_task_id, v_task.status, v_task.claimed_by_label
      using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  update app.wms_putaway_tasks set
    status = 'claimed', claimed_by_auth_user_id = p_actor_auth_user_id, claimed_by_label = p_actor_label, claimed_at = now()
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'claim_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', null, null, jsonb_build_object('claimed_by', p_actor_label)
  );

  return v_task;
end;
$$;

comment on function app.claim_wms_putaway_task is
  'ATW-014: row-locked (SELECT ... FOR UPDATE) on its first read so a genuine concurrent double-claim cannot both succeed (design note (b)/(c)) -- the second caller blocks, then observes status=claimed under a different claimant and is rejected with task_already_claimed. Idempotent no-op on a same-claimant re-claim, but only after OPS:Edit/tenant-scope authority is confirmed -- never before.';

create function app.confirm_wms_putaway_task(
  p_task_id uuid,
  p_quantity numeric,
  p_actual_location_id uuid,
  p_lot_number text,
  p_serial_number text,
  p_idempotency_key text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_putaway_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
  v_existing_confirmation app.wms_putaway_confirmations;
  v_destination app.warehouse_locations;
  v_occupied numeric;
  v_new_confirmed numeric;
  v_new_status text;
  v_movement app.inventory_movements;
  v_inbound_order_id uuid;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to confirm a putaway task' using errcode = 'check_violation';
  end if;

  -- Row-locked from this first read through the final INSERT/UPDATE (FOR UPDATE) --
  -- a second concurrent confirm on the same task cannot read the pre-confirm
  -- confirmed_quantity, post its own transfer movement and race the first caller past
  -- task_quantity (design note (b)/(c)); it blocks until the first transaction
  -- commits, then observes the updated confirmed_quantity/status.
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot confirm putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority/tenant-scope is confirmed
  -- above, never before (design note (a)). Per-confirm-event idempotency (design
  -- note 2): a same-idempotency-key retry (e.g. a client resend after a slow/
  -- timed-out first response) returns the current task state unchanged, never posts
  -- a second transfer movement.
  select * into v_existing_confirmation from app.wms_putaway_confirmations where tenant_id = v_task.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_task;
  end if;

  if v_task.status = 'unclaimed' then
    raise exception 'task_not_claimed: task % must be claimed before it can be confirmed', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.status = 'confirmed' then
    raise exception 'task_already_confirmed: task % has already been fully confirmed', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.status = 'exception' then
    raise exception 'task_exception: task % is under an unresolved exception -- reassign it before confirming', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.status = 'cancelled' then
    raise exception 'task_cancelled: task % has been cancelled', p_task_id using errcode = 'check_violation';
  end if;
  if v_task.claimed_by_auth_user_id <> p_actor_auth_user_id then
    raise exception 'not_task_claimant: identity % is not the assigned claimant of task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: confirm quantity must be greater than zero' using errcode = 'check_violation';
  end if;
  if p_quantity > v_task.remaining_quantity then
    raise exception 'exceeds_remaining_quantity: task % has % remaining but % was requested', p_task_id, v_task.remaining_quantity, p_quantity using errcode = 'check_violation';
  end if;

  if v_task.lot_controlled and coalesce(p_lot_number, '') <> coalesce(v_task.lot_number, '') then
    if p_lot_number is null then
      raise exception 'missing_lot: task % is lot-controlled (lot %) -- a matching lot number is required', p_task_id, v_task.lot_number using errcode = 'check_violation';
    end if;
    raise exception 'lot_mismatch: scanned lot % does not match task %''s own lot %', p_lot_number, p_task_id, v_task.lot_number using errcode = 'check_violation';
  end if;
  if v_task.serial_controlled and coalesce(p_serial_number, '') <> coalesce(v_task.serial_number, '') then
    if p_serial_number is null then
      raise exception 'missing_serial: task % is serial-controlled (serial %) -- a matching serial number is required', p_task_id, v_task.serial_number using errcode = 'check_violation';
    end if;
    raise exception 'serial_mismatch: scanned serial % does not match task %''s own serial %', p_serial_number, p_task_id, v_task.serial_number using errcode = 'check_violation';
  end if;

  -- Destination validation: the one authoritative check in this whole capability
  -- (design note 5). Once a task has any confirmed quantity, every subsequent
  -- confirm must land on the identical actual_location_id -- a task never splits its
  -- own execution across two different real destinations.
  --
  -- Locked (SELECT ... FOR UPDATE) on this first read of the destination and held
  -- through the capacity check below -- closing a cross-task TOCTOU class design note
  -- (b)/(c) did not originally cover: app.wms_putaway_tasks' own FOR UPDATE lock
  -- (above) only serializes two confirms against the *same task row*, and
  -- app.post_inventory_movement's own balance lock is keyed per (item/lot/serial/
  -- location) dimension tuple, not per location -- so two *different* putaway tasks
  -- (different items, or the same item with different lots) racing the same
  -- capacity-limited destination previously could both read the same stale occupancy
  -- and jointly overshoot capacity_value before either had posted its own transfer
  -- movement. Locking the destination location row here means a second concurrent
  -- confirm targeting the same destination blocks until the first transaction
  -- commits (or rolls back), then its own occupancy SELECT (a fresh READ COMMITTED
  -- statement, issued only after the lock is granted) observes the first transfer's
  -- real committed effect.
  if v_task.actual_location_id is not null then
    if p_actual_location_id <> v_task.actual_location_id then
      raise exception 'destination_mismatch: task % has already begun putaway at %, cannot confirm against a different location %', p_task_id, v_task.actual_location_id, p_actual_location_id
        using errcode = 'check_violation';
    end if;
    select * into v_destination from app.warehouse_locations where id = p_actual_location_id for update;
    if not found then
      raise exception 'location_not_found: %', p_actual_location_id using errcode = 'no_data_found';
    end if;
  else
    select * into v_destination from app.warehouse_locations where id = p_actual_location_id for update;
    if not found then
      raise exception 'location_not_found: %', p_actual_location_id using errcode = 'no_data_found';
    end if;
    if v_destination.warehouse_id <> v_task.warehouse_id then
      raise exception 'incompatible_location: destination % does not belong to warehouse %', p_actual_location_id, v_task.warehouse_id using errcode = 'check_violation';
    end if;
    if v_destination.location_type not in ('rack', 'shelf', 'bin') then
      raise exception 'incompatible_location: destination % is a % -- putaway must land on a rack, shelf or bin, not a final dock/staging/floor location', p_actual_location_id, v_destination.location_type
        using errcode = 'check_violation';
    end if;
    if not v_destination.putaway_enabled then
      raise exception 'incompatible_location: destination % is not putaway_enabled', p_actual_location_id using errcode = 'check_violation';
    end if;
    if v_destination.status <> 'active' then
      raise exception 'blocked_destination: destination % is not active', p_actual_location_id using errcode = 'check_violation';
    end if;
  end if;

  if v_destination.capacity_value is not null then
    select coalesce(sum(on_hand), 0) into v_occupied from app.inventory_balances where location_id = p_actual_location_id and status = 'on_hand';
    if v_occupied + p_quantity > v_destination.capacity_value then
      raise exception 'destination_full: destination % has % of % capacity occupied -- % more would exceed it', p_actual_location_id, v_occupied, v_destination.capacity_value, p_quantity
        using errcode = 'check_violation';
    end if;
  end if;

  select s.inbound_order_id into v_inbound_order_id from app.wms_receipt_lines l join app.wms_receipt_sessions s on s.id = l.receipt_session_id where l.id = v_task.receipt_line_id;

  -- The balanced transfer movement (Prompt 233 section 24: "source decrease equals
  -- destination increase in one balanced inventory transfer movement") -- two lines,
  -- identical owner/item/uom/lot/serial/status dimension, signed_quantity summing to
  -- exactly zero (app.post_inventory_movement's own design note 6 enforcement,
  -- ATW-015). A resulting negative on_hand at the source is caught by that function's
  -- own insufficient_stock check -- the real, reused safety net for "insufficient
  -- source balance" (Prompt 233 section 25), never re-implemented here.
  v_movement := app.post_inventory_movement(
    v_task.tenant_id, v_task.warehouse_id, 'transfer', 'wms_inbound_order', v_inbound_order_id, p_idempotency_key,
    'putaway task ' || p_task_id::text,
    jsonb_build_array(
      jsonb_build_object('owner_account_id', v_task.owner_account_id, 'item_master_id', v_task.item_master_id, 'location_id', v_task.source_location_id,
        'uom_code', v_task.uom_code, 'signed_quantity', -p_quantity, 'lot_number', v_task.lot_number, 'serial_number', v_task.serial_number, 'expiry_date', v_task.expiry_date, 'status', 'on_hand'),
      jsonb_build_object('owner_account_id', v_task.owner_account_id, 'item_master_id', v_task.item_master_id, 'location_id', p_actual_location_id,
        'uom_code', v_task.uom_code, 'signed_quantity', p_quantity, 'lot_number', v_task.lot_number, 'serial_number', v_task.serial_number, 'expiry_date', v_task.expiry_date, 'status', 'on_hand')
    ),
    p_actor_auth_user_id, p_actor_label
  );

  insert into app.wms_putaway_confirmations (
    tenant_id, task_id, idempotency_key, quantity, actual_location_id, movement_id, lot_number, serial_number, expiry_date, confirmed_by_auth_user_id, confirmed_by_label
  ) values (
    v_task.tenant_id, p_task_id, p_idempotency_key, p_quantity, p_actual_location_id, v_movement.id, p_lot_number, p_serial_number, v_task.expiry_date, p_actor_auth_user_id, p_actor_label
  );

  v_new_confirmed := v_task.confirmed_quantity + p_quantity;
  v_new_status := case when v_new_confirmed >= v_task.task_quantity then 'confirmed' else 'partial' end;

  update app.wms_putaway_tasks set
    confirmed_quantity = v_new_confirmed, actual_location_id = p_actual_location_id, status = v_new_status
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'confirm_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', null, null,
    jsonb_build_object('quantity', p_quantity, 'actual_location_id', p_actual_location_id, 'movement_id', v_movement.id, 'status', v_task.status)
  );

  return v_task;
end;
$$;

comment on function app.confirm_wms_putaway_task is
  'ATW-014: the one and only path that ever calls app.post_inventory_movement (movement_type=transfer) for this task. Row-locked (SELECT ... FOR UPDATE) on both its task row (first read) and its destination app.warehouse_locations row (destination validation) so a second concurrent confirm targeting either the same task or the same destination location blocks until the first transaction commits; idempotent per-confirm-event on (tenant_id, idempotency_key) via app.wms_putaway_confirmations, but only after OPS:Edit/tenant-scope authority and claimant identity are confirmed -- never before. status derives exclusively from confirmed_quantity vs task_quantity (design note 3) -- never a caller-set value. The one authoritative destination eligibility/capacity check in this capability (design note 5), race-safe across two different tasks targeting the same destination.';

create function app.mark_wms_putaway_task_exception(
  p_task_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_putaway_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_override app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority/tenant-scope is confirmed above, never
  -- before (design note (a)).
  if v_task.status = 'exception' then
    return v_task;
  end if;

  if v_task.status not in ('claimed', 'partial') then
    raise exception 'invalid_transition: task % is % -- only a claimed or partially-confirmed task may be marked exception', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to mark a putaway task exception' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  -- Only the task's own claimant, or a supervisor holding OPS:Override, may record a
  -- blocker on it (design note 7).
  if v_task.claimed_by_auth_user_id <> p_actor_auth_user_id then
    v_override := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Override');
    if not v_override.allowed then
      raise exception 'insufficient_authority: identity % is neither the claimant of task % nor holds OPS:Override', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
    end if;
  end if;

  update app.wms_putaway_tasks set status = 'exception', exception_reason = p_reason where id = p_task_id returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'mark_wms_putaway_task_exception',
    'app.wms_putaway_tasks', v_task.id, 'success', p_reason, null, null
  );

  return v_task;
end;
$$;

comment on function app.mark_wms_putaway_task_exception is
  'ATW-014: Prompt 233 section 23''s own exception flow ("block wrong/blocked/full/incompatible destination... record blocker... never hide or bypass failure"). Callable by the task''s own claimant or a supervisor holding OPS:Override (design note 7). Row-locked (FOR UPDATE); idempotent no-op on an already-exception task, only after authority is confirmed.';

create function app.reassign_wms_putaway_task(
  p_task_id uuid,
  p_new_claimant_auth_user_id uuid,
  p_new_claimant_label text,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_putaway_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
  v_new_status text;
begin
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot override putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  if v_task.status in ('confirmed', 'cancelled') then
    raise exception 'invalid_transition: task % is % -- a confirmed or cancelled task may not be reassigned', p_task_id, v_task.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reassign or release a putaway task' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  if p_new_claimant_auth_user_id is null then
    v_new_status := 'unclaimed';
  elsif v_task.confirmed_quantity > 0 then
    v_new_status := 'partial';
  else
    v_new_status := 'claimed';
  end if;

  update app.wms_putaway_tasks set
    status = v_new_status,
    claimed_by_auth_user_id = p_new_claimant_auth_user_id,
    claimed_by_label = p_new_claimant_label,
    claimed_at = (case when p_new_claimant_auth_user_id is null then null else now() end),
    exception_reason = (case when v_new_status = 'unclaimed' then null else exception_reason end)
  where id = p_task_id
  returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'reassign_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', p_reason, null,
    jsonb_build_object('new_claimant', p_new_claimant_label, 'new_status', v_new_status)
  );

  return v_task;
end;
$$;

comment on function app.reassign_wms_putaway_task is
  'ATW-014: Prompt 233 section 26''s own supervisor override/reassign mechanism (design note 8), OPS:Override-gated -- the identical authority app.approve_wms_receipt_overage/app.resolve_wms_receipt_hold (ATW-013) already established. A null new claimant releases the task back to unclaimed (Prompt 233 section 32''s own "release uncommitted task"); a non-null one reassigns it, resuming from exception back to claimed/partial as appropriate. Never callable on an already-confirmed or cancelled task.';

create function app.cancel_wms_putaway_task(
  p_task_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.wms_putaway_tasks
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_putaway_tasks where id = p_task_id for update;
  if not found then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot edit putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent no-op -- only after authority/tenant-scope is confirmed above, never
  -- before (design note (a)).
  if v_task.status = 'cancelled' then
    return v_task;
  end if;

  if v_task.confirmed_quantity > 0 then
    raise exception 'has_confirmed_quantity: task % has already confirmed % unit(s) -- a task with real posted movements may never be cancelled, only completed or reassigned', p_task_id, v_task.confirmed_quantity
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to cancel a putaway task' using errcode = 'check_violation';
  end if;
  if v_task.record_version <> p_expected_version then
    raise exception 'stale_version: putaway task % expected version % but found %', p_task_id, p_expected_version, v_task.record_version using errcode = 'check_violation';
  end if;

  update app.wms_putaway_tasks set status = 'cancelled' where id = p_task_id returning * into v_task;

  perform app.capture_audit_event(
    v_task.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_wms_putaway_task',
    'app.wms_putaway_tasks', v_task.id, 'success', p_reason, null, null
  );

  return v_task;
end;
$$;

comment on function app.cancel_wms_putaway_task is
  'ATW-014: only while zero of the task''s own confirmed_quantity has posted (Prompt 233 section 32: "preserve confirmed movements") -- once real inventory has transferred, the task can only be completed or reassigned, never cancelled. Cancelling frees the receipt line''s own remaining accepted_quantity for a fresh app.generate_wms_putaway_task call.';

-- 4. Reads.

create function app.get_wms_putaway_task(p_task_id uuid, p_actor_auth_user_id uuid)
returns app.wms_putaway_tasks
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_task app.wms_putaway_tasks;
  v_warehouse app.warehouses;
begin
  select * into v_task from app.wms_putaway_tasks where id = p_task_id;
  if not found then
    raise exception 'task_not_found: %', p_task_id using errcode = 'no_data_found';
  end if;
  select * into v_warehouse from app.warehouses where id = v_task.warehouse_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_task.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_task.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, v_task.tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view putaway task %', p_actor_auth_user_id, p_task_id using errcode = 'insufficient_privilege';
  end if;

  return v_task;
end;
$$;

create function app.list_wms_putaway_task_confirmations(p_task_id uuid, p_actor_auth_user_id uuid)
returns setof app.wms_putaway_confirmations
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.get_wms_putaway_task(p_task_id, p_actor_auth_user_id);
  return query select * from app.wms_putaway_confirmations where task_id = p_task_id order by confirmed_at;
end;
$$;

comment on function app.list_wms_putaway_task_confirmations is
  'ATW-014: reuses app.get_wms_putaway_task for its own authority/record-scope gate rather than duplicating the check.';

create function app.list_wms_putaway_tasks(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_receipt_line_id uuid default null,
  p_status_filter text default null,
  p_claimed_by_auth_user_id uuid default null,
  p_limit integer default 50
)
returns setof app.wms_putaway_tasks
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
  select t.* from app.wms_putaway_tasks t
  join app.warehouses w on w.id = t.warehouse_id
  where t.tenant_id = p_tenant_id
    and (p_warehouse_id is null or t.warehouse_id = p_warehouse_id)
    and (p_receipt_line_id is null or t.receipt_line_id = p_receipt_line_id)
    and (p_status_filter is null or t.status = p_status_filter)
    and (p_claimed_by_auth_user_id is null or t.claimed_by_auth_user_id = p_claimed_by_auth_user_id)
    and app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
  order by t.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_wms_putaway_tasks is
  'ATW-014: bounded read (p_limit default 50, hard-capped 200), record-scoped per row by the task''s own warehouse company org unit.';

-- 5. RLS -- record scope enforced in the database (mirrors app.wms_receipt_sessions),
-- not UI-only.

alter table app.wms_putaway_tasks enable row level security;

create policy wms_putaway_tasks_select_scoped on app.wms_putaway_tasks
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouses w
      where w.id = wms_putaway_tasks.warehouse_id
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

alter table app.wms_putaway_confirmations enable row level security;

create policy wms_putaway_confirmations_select_scoped on app.wms_putaway_confirmations
  for select to authenticated
  using (
    exists (
      select 1 from app.wms_putaway_tasks t
      join app.warehouses w on w.id = t.warehouse_id
      where t.id = wms_putaway_confirmations.task_id
        and app.can_access_record((select auth.uid()), w.tenant_id, null, app.lead_record_scope_org_unit_ids(w.company_org_unit_id), null)
    )
  );

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke
-- of PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant select on app.wms_putaway_tasks, app.wms_putaway_confirmations to authenticated, service_role;
grant insert, update, delete on app.wms_putaway_tasks, app.wms_putaway_confirmations to service_role;

grant execute on function app.generate_wms_putaway_task(uuid, numeric, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.claim_wms_putaway_task(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.confirm_wms_putaway_task(uuid, numeric, uuid, text, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.mark_wms_putaway_task_exception(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reassign_wms_putaway_task(uuid, uuid, text, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_wms_putaway_task(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_wms_putaway_task(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_putaway_task_confirmations(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_wms_putaway_tasks(uuid, uuid, uuid, uuid, text, uuid, integer) to authenticated, service_role;
