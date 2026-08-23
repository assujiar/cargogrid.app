-- Advanced TMS/WMS capability ATW-022 (CG-S10-ATW-022, Prompt 241, "Warehouse
-- Billing Events") -- source-linked warehouse billing events and a compatible
-- Finance handoff, WITHOUT creating invoices, receivables, payables or journals
-- in WMS (Prompt 241 objective, verbatim). Follows immediately after ATW-021
-- (Label and Barcode Operations, VERIFIED).
--
-- Upstream, read directly (never re-derived, never edited):
-- * OPS-181 (`20260728140000_create_operations_billing_readiness.sql`) -- the exact
--   "verified Finance billing/readiness handoff" shape this migration mirrors: a
--   versioned, never-edited-in-place evidence/calculation row, plus a separate
--   append-only Finance-handoff row, a plain synchronous RPC (never routed through
--   `app.jobs`). `docs/build-log/phase-03/OPERATIONS_DOWNSTREAM_CONTRACTS.md` states
--   Operations' own boundary ("no invoice, AR, GL, or journal entry exists anywhere
--   in this repository"); this migration makes the identical claim true for
--   warehouse activity.
-- * ATW-019 (`20260730260000_..._wms_outbound.sql`) -- `app.wms_billing_eligibility_
--   events` (one row per shipment, a blind cross-UOM `total_quantity` -- never billed
--   off directly) and `app.wms_shipment_issue_lines` (the real per-line/per-UOM
--   evidence, read via `app.list_wms_shipment_issue_lines`, not used directly by
--   capture -- capture instead reads the terminal `wms_billing_eligibility_events` row
--   itself for the 'outbound' activity_type, exactly as designed below). No
--   equivalent eligibility-event table exists for storage/receiving/handling/putaway/
--   pick/pack/value_added -- capture reads the already-VERIFIED operational tables
--   directly for those (dispatch table below).
-- * COM-156 (`20260724300000_..._customer_contract_pricing.sql`) -- `app.
--   customer_contracts`' own header/versioning/publish lifecycle is reused directly
--   (`app.warehouse_billing_rate_components` is a NEW child table of that EXISTING
--   header, never a second contract root). `customer_contract_price_components` is
--   lane/mode/equipment-shaped, not activity/UOM-shaped, so it is not reused for the
--   line data itself.
-- * FIN-194/FIN-195 (`20260728230000_.../20260729090000_...`) -- `app.apply_finance_
--   rounding`, `app.validate_currency_code`, `app.convert_finance_amount`'s own
--   rounding-config-resolution chain, and `app.calculate_finance_tax` (the shared,
--   deterministic tax service) are all reused directly, never reimplemented.
-- * ATW-011A (`20260730160000_..._item_uom_master.sql`) -- `app.convert_uom_quantity`/
--   `app.validate_uom_code` reused directly for UOM normalization.
-- * `server/contracts/inventory-ledger/inventory-ledger.ts` and
--   `server/contracts/label-barcode/label-barcode.ts` -- the exact TypeScript
--   service-layer pattern this checkpoint's own `server/{contracts,queries,
--   mutations}/warehouse-billing.ts` replicate.
--
-- Corrections to this task's own brief, verified directly against the real upstream
-- migrations rather than assumed (disclosed per the brief's own instruction):
-- 1. **`app.wms_receipt_lines` is the real 'wms_receipt_line' dispatch target**,
--    eligible state is `status = 'committed'` (confirmed directly -- ATW-013's own
--    `wms_receipt_lines_status_check`: `pending` -> `counted` -> `committed`). It DOES
--    carry a real `record_version` (a touch-triggered table), so `source_version`
--    is genuinely read from it, not fabricated.
-- 2. **'wms_putaway_confirmation' dispatches to `app.wms_putaway_tasks` (status =
--    'confirmed'), NOT `app.wms_putaway_confirmations`.** The confirmations table is
--    genuinely append-only evidence with NO `record_version` column at all (by
--    design, ATW-014's own header) -- there is no live "current version" to snapshot
--    from it. `wms_putaway_tasks` DOES carry a real, touch-triggered `record_version`
--    and its own `status` CHECK includes `'confirmed'` (verified directly). Same
--    correction for 'wms_pick_task_confirmation' -> `app.wms_pick_tasks` (status in
--    `('picked', 'short')`, both real, verified CHECK values) and
--    'wms_package_confirmation' -> `app.wms_packages` (status = 'confirmed', verified
--    -- `wms_packages_status_check` is exactly `('open', 'confirmed')`).
-- 3. **`app.wms_billing_eligibility_events` has NO `record_version` column at all**
--    (genuinely append-only by construction, one row per shipped shipment, never
--    updated -- confirmed directly against ATW-019's own DDL). This migration's own
--    "read the source row's own record_version as source_version" rule is therefore
--    structurally inapplicable to this one source_type; `source_version` is fixed at
--    `1` for every 'wms_billing_eligibility_event' capture (disclosed, not a silent
--    fabrication -- the row itself can never change underneath a captured event, so a
--    fixed version is the exact semantic equivalent of "the row's own version never
--    moves").
-- 4. **`app.warehouse_billing_events.tax_code` is plain `text`, NOT a real FK to
--    `app.finance_tax_codes(code)`.** Verified directly: `app.finance_tax_codes` has
--    no unique constraint on `code` alone (only on `(coalesce(tenant_id, ...), code)`,
--    since a tenant-scoped code and a platform-wide code may legitimately share the
--    same code string) -- a plain-column FK to `code` is not even creatable. Real
--    validation happens where it already lives: `app.calculate_finance_tax` itself
--    raises `finance_tax_rule_missing` for an unresolvable code, exactly the same
--    validation-at-the-real-service-boundary discipline this migration already
--    applies everywhere else.
-- 5. **`app.customer_contracts`' own mutation RPCs do NOT call `app.can_access_record`
--    at all** (verified directly against `app.create_customer_contract_draft`/`app.
--    add_customer_contract_price_component`/`app.publish_customer_contract` --
--    contracts are tenant-wide-visible reference data, matching their own RLS
--    policy's comment: "mirrors app.accounts' own posture"). This migration's own
--    `app.create_warehouse_billing_rate_component` therefore also does NOT add a
--    separate record-scope check beyond tenant-level `COM:Edit` -- adding one would
--    be a fabricated gate this capability's own real precedent does not have.
--
-- Design decisions not fully pinned down by the brief (disclosed):
-- * **The two correction/reversal RPCs (`app.correct_warehouse_billing_event`/`app.
--   reverse_warehouse_billing_event`) do NOT literally call `app.capture_warehouse_
--   billing_event`.** The brief's own phrasing ("exposed here so those two can
--   compose this same function") was read literally first; doing so would force a
--   LIVE re-read/re-validation of the backing operational source row at correction/
--   reversal time, directly contradicting this same migration's own "source_version
--   is an evidence snapshot, never re-read live after capture" rule, and would also
--   incorrectly re-run the "one active event per source" partial-unique-index guard
--   against the ORIGINAL event's own still-un-corrected row. Both RPCs instead
--   perform their own direct, narrowly-scoped INSERT copying the named fields from
--   the original row -- never re-touching the live source table.
-- * **`app.reverse_warehouse_billing_event`'s new row is inserted as `status =
--   'pending_review'`, not `'draft'` as the brief's literal text states.** A
--   reversal's own amounts are the exact negation of the original's already-
--   calculated values (never recalculated) -- if the new row were left in `'draft'`,
--   nothing would structurally stop a later `app.calculate_warehouse_billing_event`
--   call from overwriting that negation with a freshly-resolved rate (status='draft'
--   is exactly that function's own gate), directly contradicting "a reversal does
--   not recalculate." The brief's own review/approve/handoff description for reversal
--   never mentions a calculate step at all, so starting at `pending_review` (skipping
--   calculate entirely, matching the actual intended cycle) resolves the
--   contradiction. `app.correct_warehouse_billing_event`'s new row, by contrast, IS
--   inserted as real `'draft'` exactly as specified -- a correction's whole point is
--   a fresh, real recalculation against the corrected quantity.
-- * Rate-basis-shape validity (`rate_uom_code`/`tier_schedule`/`time_basis_unit`
--   required-or-forbidden per `rate_basis`) is enforced BOTH as a real table-level
--   CHECK constraint (via `app.validate_warehouse_billing_tier_schedule` for the
--   tier-ascending rule specifically, mirroring `app.validate_currency_code`'s own
--   function-in-a-CHECK precedent) AND as an explicit, named early validation inside
--   `app.create_warehouse_billing_rate_component` (a clear `invalid_tier_schedule`/
--   etc. message rather than a raw `check_violation` with only a constraint name).
-- * A private (never `authenticated`/`service_role`-granted) internal helper, `app.
--   compute_warehouse_billing_breakdown`, holds the ONE real calculation
--   implementation (`rate_basis` dispatch, UOM conversion, minimum floor, rounding,
--   tax) -- `app.calculate_warehouse_billing_event`, `app.recalculate_warehouse_
--   billing_event` and `app.preview_warehouse_billing_calculation` all call it, never
--   duplicating the arithmetic divergently (the brief's own "factor it into one
--   shared internal function" instruction, honored literally here). It needs no
--   explicit grant -- every caller is itself a SECURITY DEFINER function owned by the
--   same migration-applying role, and Postgres privilege checks for a nested call
--   made from inside a SECURITY DEFINER function's body run as that function's own
--   OWNER, which already holds implicit rights to every object it created (the same
--   reliance every other migration in this repository already has on `app.capture_
--   audit_event`/`app.post_inventory_movement` needing no per-caller re-grant).
-- * `app.preview_warehouse_billing_calculation`'s own signature (per the brief,
--   exactly 8 positional params) has no `p_tax_code` parameter at all -- its own
--   breakdown is therefore always computed with `p_tax_code = null` (base_amount/
--   total only, no tax preview). Disclosed as a real, bounded limitation rather than
--   silently widening the brief's own exact signature.
-- * `app.list_warehouse_billing_rate_components` is gated `COM:View` (matching the
--   create RPC's own `COM:Edit` commercial-ownership tier), tenant-wide (mirrors
--   `app.customer_contract_price_components`' own tenant-wide read posture) -- the
--   brief names no explicit gate for this one read.
--
-- Residual scope (disclosed, matches every ATW-012..021 checkpoint's own identical
-- boundary): NO app/ route, NO REST/GraphQL surface this checkpoint. Read-only
-- service-layer wrappers exist (`server/{contracts,queries,mutations}/warehouse-
-- billing.ts`) for a future UI/API checkpoint to consume directly.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its own
-- explicit REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC statement before
-- its final grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 1. app.warehouse_billing_rate_components -- a child of the EXISTING
--    app.customer_contracts header (COM-156). Never a second contract root.
-- ===========================================================================

create function app.validate_warehouse_billing_tier_schedule(p_tier_schedule jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_elem jsonb;
  v_threshold numeric;
  v_rate numeric;
  v_prev numeric;
  v_has_prev boolean := false;
begin
  if p_tier_schedule is null then
    return true;
  end if;
  if jsonb_typeof(p_tier_schedule) <> 'array' or jsonb_array_length(p_tier_schedule) = 0 then
    return false;
  end if;

  for v_elem in select value from jsonb_array_elements(p_tier_schedule) loop
    if jsonb_typeof(v_elem) <> 'object' or not (v_elem ? 'threshold') or not (v_elem ? 'rate') then
      return false;
    end if;
    begin
      v_threshold := (v_elem ->> 'threshold')::numeric;
      v_rate := (v_elem ->> 'rate')::numeric;
    exception when others then
      return false;
    end;
    if v_threshold is null or v_rate is null or v_threshold <= 0 or v_rate < 0 then
      return false;
    end if;
    if v_has_prev and v_threshold <= v_prev then
      return false;
    end if;
    v_prev := v_threshold;
    v_has_prev := true;
  end loop;

  return true;
end;
$$;

comment on function app.validate_warehouse_billing_tier_schedule is
  'ATW-022: true iff p_tier_schedule is null, OR a non-empty JSON array of {"threshold": numeric>0, "rate": numeric>=0} objects with strictly ascending threshold. Used both as a real table-level CHECK (defense in depth against a raw service_role insert) and re-checked explicitly in app.create_warehouse_billing_rate_component for a clear invalid_tier_schedule message.';

create table app.warehouse_billing_rate_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  contract_id uuid not null references app.customer_contracts (id),
  warehouse_id uuid references app.warehouses (id),
  activity_type text not null,
  rate_basis text not null,
  rate_uom_code text references app.uoms (code),
  unit_rate numeric not null,
  minimum_amount numeric,
  currency text not null references app.finance_currencies (code),
  tier_schedule jsonb,
  time_basis_unit text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouse_billing_rate_components_activity_type_check check (
    activity_type in ('storage', 'receiving', 'handling', 'putaway', 'pick', 'pack', 'outbound', 'value_added')
  ),
  constraint warehouse_billing_rate_components_rate_basis_check check (rate_basis in ('flat', 'per_unit', 'tiered', 'time_basis')),
  constraint warehouse_billing_rate_components_unit_rate_check check (unit_rate >= 0),
  constraint warehouse_billing_rate_components_minimum_amount_check check (minimum_amount is null or minimum_amount >= 0),
  constraint warehouse_billing_rate_components_rate_uom_shape_check check ((rate_basis = 'flat') = (rate_uom_code is null)),
  constraint warehouse_billing_rate_components_tier_schedule_shape_check check (
    case when rate_basis = 'tiered' then tier_schedule is not null and jsonb_array_length(tier_schedule) > 0 else tier_schedule is null end
  ),
  constraint warehouse_billing_rate_components_tier_schedule_valid_check check (
    rate_basis <> 'tiered' or app.validate_warehouse_billing_tier_schedule(tier_schedule)
  ),
  constraint warehouse_billing_rate_components_time_basis_shape_check check ((rate_basis = 'time_basis') = (time_basis_unit is not null))
);

comment on table app.warehouse_billing_rate_components is
  'ATW-022: a child of the EXISTING app.customer_contracts header (COM-156) -- reuses its own tenant_id/account_id/status/effective_from/effective_to/versioning, never a second contract root. Design note: this table''s own mutation RPC (app.create_warehouse_billing_rate_component) is gated COM:Edit (not OPS), since it extends a Commercial-owned contract''s own pricing configuration -- the event capture/review/approval/handoff lifecycle below is gated OPS, matching Prompt 241 section 26''s own explicit commercial-vs-operational authority split. No separate set_..._status RPC exists -- rate components live and die with their own contract''s own publish/retire lifecycle.';

create unique index warehouse_billing_rate_components_scope_unique on app.warehouse_billing_rate_components (
  contract_id, activity_type, coalesce(warehouse_id, '00000000-0000-0000-0000-000000000000'::uuid)
);
create index warehouse_billing_rate_components_contract_idx on app.warehouse_billing_rate_components (contract_id);
create index warehouse_billing_rate_components_tenant_warehouse_idx on app.warehouse_billing_rate_components (tenant_id, warehouse_id);

create function app.touch_warehouse_billing_rate_components_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger warehouse_billing_rate_components_touch_row
  before update on app.warehouse_billing_rate_components
  for each row
  execute function app.touch_warehouse_billing_rate_components_row();

-- ===========================================================================
-- 2. app.warehouse_billing_events -- versioned, is_current-free (corrections/
--    reversals are separate new rows, never an in-place amount rewrite).
-- ===========================================================================

create table app.warehouse_billing_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  warehouse_id uuid not null references app.warehouses (id),
  owner_account_id uuid not null references app.accounts (id),
  activity_type text not null,
  source_type text not null,
  source_id uuid,
  source_version integer,
  activity_date timestamptz not null,
  quantity numeric not null,
  uom_code text not null references app.uoms (code),
  contract_id uuid references app.customer_contracts (id),
  rate_component_id uuid references app.warehouse_billing_rate_components (id),
  base_amount numeric,
  tax_code text,
  tax_rule_version_id uuid references app.finance_tax_rule_versions (id),
  tax_amount numeric,
  total_amount numeric,
  currency text references app.finance_currencies (code),
  rounding_mode text,
  calculation_explanation jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  hold_reason text,
  reviewed_by_auth_user_id uuid references auth.users (id),
  reviewed_by_label text,
  reviewed_at timestamptz,
  approved_by_auth_user_id uuid references auth.users (id),
  approved_by_label text,
  approved_at timestamptz,
  corrects_event_id uuid references app.warehouse_billing_events (id),
  reverses_event_id uuid references app.warehouse_billing_events (id),
  correction_reason text,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint warehouse_billing_events_activity_type_check check (
    activity_type in ('storage', 'receiving', 'handling', 'putaway', 'pick', 'pack', 'outbound', 'value_added')
  ),
  constraint warehouse_billing_events_source_type_check check (
    source_type in ('wms_receipt_line', 'wms_putaway_confirmation', 'wms_pick_task_confirmation', 'wms_package_confirmation', 'wms_billing_eligibility_event', 'manual')
  ),
  constraint warehouse_billing_events_source_id_shape_check check (source_type = 'manual' or source_id is not null),
  constraint warehouse_billing_events_source_version_shape_check check (source_type = 'manual' or source_version is not null),
  constraint warehouse_billing_events_quantity_check check (quantity > 0),
  constraint warehouse_billing_events_status_check check (
    status in ('draft', 'pending_review', 'reviewed', 'approved', 'on_hold', 'handed_off', 'corrected', 'reversed')
  ),
  constraint warehouse_billing_events_not_both_correction_check check (not (corrects_event_id is not null and reverses_event_id is not null)),
  constraint warehouse_billing_events_no_self_correct_check check (id <> corrects_event_id),
  constraint warehouse_billing_events_no_self_reverse_check check (id <> reverses_event_id),
  constraint warehouse_billing_events_correction_reason_check check (
    (corrects_event_id is null and reverses_event_id is null) or (correction_reason is not null and length(trim(correction_reason)) > 0)
  ),
  constraint warehouse_billing_events_calculated_shape_check check (
    status = 'draft' or (base_amount is not null and total_amount is not null and currency is not null and rounding_mode is not null)
  ),
  constraint warehouse_billing_events_tax_amount_shape_check check (base_amount is null or tax_amount is not null),
  constraint warehouse_billing_events_total_amount_check check (total_amount is null or total_amount = base_amount + coalesce(tax_amount, 0)),
  constraint warehouse_billing_events_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.warehouse_billing_events is
  'ATW-022: the source-linked billable event. A recalculation before approval mutates the SAME draft/pending_review/reviewed row in place (legitimate pre-approval iteration); a correction/reversal after approval/handoff is always a brand-NEW row (corrects_event_id/reverses_event_id), and the ORIGINAL row''s own base_amount/tax_amount/total_amount/calculation_explanation are never rewritten -- only its status changes to corrected/reversed (Prompt 241''s own "no silent amount rewrite after handoff" rule).';

create index warehouse_billing_events_tenant_warehouse_status_idx on app.warehouse_billing_events (tenant_id, warehouse_id, status);
create index warehouse_billing_events_tenant_owner_idx on app.warehouse_billing_events (tenant_id, owner_account_id);
create index warehouse_billing_events_contract_idx on app.warehouse_billing_events (contract_id);
create index warehouse_billing_events_source_idx on app.warehouse_billing_events (source_type, source_id);
create index warehouse_billing_events_corrects_idx on app.warehouse_billing_events (corrects_event_id);
create index warehouse_billing_events_reverses_idx on app.warehouse_billing_events (reverses_event_id);

-- "One source activity/version and billing rule yields at most one active billing
-- event" (Prompt 241 section 24) -- deliberately excludes corrections/reversals
-- (explicitly, intentionally tied back to a prior event -- corrects_event_id/
-- reverses_event_id is set) and 'manual' (no real source_id to dedupe on; manual
-- entries rely on idempotency_key alone plus the mandatory OPS:Override gate).
create unique index warehouse_billing_events_one_active_per_source_idx on app.warehouse_billing_events (tenant_id, source_type, source_id, source_version)
  where corrects_event_id is null and reverses_event_id is null and source_type <> 'manual';

-- At most one reversal per original event -- a real DB-enforced guarantee.
create unique index warehouse_billing_events_one_reversal_per_original_idx on app.warehouse_billing_events (reverses_event_id)
  where reverses_event_id is not null;

-- At most one correction per original event -- a real DB-enforced guarantee,
-- symmetric with the reversal index above (previously relied solely on the
-- select ... for update row lock plus an application-level exists() check).
create unique index warehouse_billing_events_one_correction_per_original_idx on app.warehouse_billing_events (corrects_event_id)
  where corrects_event_id is not null;

create function app.touch_warehouse_billing_events_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger warehouse_billing_events_touch_row
  before update on app.warehouse_billing_events
  for each row
  execute function app.touch_warehouse_billing_events_row();

-- ===========================================================================
-- 3. app.warehouse_billing_handoffs -- append-only, mirrors
--    app.billing_readiness_handoffs (OPS-181) almost exactly.
-- ===========================================================================

create table app.warehouse_billing_handoffs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  billing_event_id uuid not null references app.warehouse_billing_events (id),
  idempotency_key text not null,
  handed_off_by_auth_user_id uuid not null references auth.users (id),
  handed_off_by_label text,
  handed_off_at timestamptz not null default now(),
  reconciliation_status text,
  reconciliation_note text,
  reconciled_at timestamptz,
  updated_at timestamptz,
  created_at timestamptz not null default now(),
  constraint warehouse_billing_handoffs_billing_event_unique unique (billing_event_id),
  constraint warehouse_billing_handoffs_tenant_idempotency_unique unique (tenant_id, idempotency_key),
  constraint warehouse_billing_handoffs_reconciliation_status_check check (reconciliation_status is null or reconciliation_status in ('reconciled', 'rejected')),
  constraint warehouse_billing_handoffs_reconciliation_shape_check check (
    (reconciliation_status is null and reconciliation_note is null and reconciled_at is null)
    or (reconciliation_status is not null and reconciliation_note is not null and reconciled_at is not null)
  )
);

comment on table app.warehouse_billing_handoffs is
  'ATW-022: one append-only, idempotent Finance-handoff record per successful app.handoff_warehouse_billing_event call -- mirrors app.billing_readiness_handoffs (OPS-181) almost exactly. One handoff per event, ever (billing_event_id unique). reconciliation_status/note/reconciled_at change exactly once, later, via the dedicated service_role-only app.record_warehouse_billing_reconciliation_outcome RPC -- no blanket touch trigger on this table; updated_at is set manually inside that one RPC only.';

create index warehouse_billing_handoffs_tenant_idx on app.warehouse_billing_handoffs (tenant_id);

-- ===========================================================================
-- 4. The one, shared, real calculation implementation. Never granted execute
--    directly (internal helper only -- see this migration's own header).
-- ===========================================================================

create function app.compute_warehouse_billing_breakdown(
  p_tenant_id uuid,
  p_rate app.warehouse_billing_rate_components,
  p_quantity numeric,
  p_uom_code text,
  p_activity_date timestamptz,
  p_tax_code text,
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_converted_quantity numeric;
  v_conversion_applied boolean := false;
  v_base_amount numeric := 0;
  v_floor_applied boolean := false;
  v_currency_precision integer;
  v_mode text := 'round_half_up';
  v_precision integer;
  v_order text := 'convert_then_round';
  v_rounding_row record;
  v_tax jsonb;
  v_tax_amount numeric := 0;
  v_tax_rule_version_id uuid;
  v_total_amount numeric;
  v_explanation jsonb;
  v_tier jsonb;
  v_prev_threshold numeric := 0;
  v_remaining numeric;
  v_band numeric;
  v_threshold numeric;
  v_tier_rate numeric := 0;
begin
  if p_rate.rate_basis = 'flat' then
    v_converted_quantity := p_quantity;
    v_base_amount := p_rate.unit_rate;
  else
    if p_uom_code = p_rate.rate_uom_code then
      v_converted_quantity := p_quantity;
    else
      v_converted_quantity := app.convert_uom_quantity(p_quantity, p_uom_code, p_rate.rate_uom_code);
      v_conversion_applied := true;
    end if;

    if p_rate.rate_basis in ('per_unit', 'time_basis') then
      v_base_amount := v_converted_quantity * p_rate.unit_rate;
    elsif p_rate.rate_basis = 'tiered' then
      v_base_amount := 0;
      v_remaining := v_converted_quantity;
      v_prev_threshold := 0;
      for v_tier in select value from jsonb_array_elements(p_rate.tier_schedule) order by (value ->> 'threshold')::numeric loop
        exit when v_remaining <= 0;
        v_threshold := (v_tier ->> 'threshold')::numeric;
        v_tier_rate := (v_tier ->> 'rate')::numeric;
        v_band := least(v_remaining, v_threshold - v_prev_threshold);
        if v_band > 0 then
          v_base_amount := v_base_amount + (v_band * v_tier_rate);
          v_remaining := v_remaining - v_band;
        end if;
        v_prev_threshold := v_threshold;
      end loop;
      -- Quantity beyond the last named threshold continues to bill at the last
      -- tier's own rate (a real progressive-tier calculation, never a single lookup).
      if v_remaining > 0 then
        v_base_amount := v_base_amount + (v_remaining * v_tier_rate);
      end if;
    end if;
  end if;

  if p_rate.minimum_amount is not null and v_base_amount < p_rate.minimum_amount then
    v_floor_applied := true;
    v_base_amount := p_rate.minimum_amount;
  end if;

  select minor_unit_precision into v_currency_precision from app.finance_currencies where code = p_rate.currency;
  v_precision := coalesce(v_currency_precision, 2);

  -- Mirrors app.convert_finance_amount's own rounding-config-resolution chain
  -- exactly (FIN-194) -- key 'warehouse_billing' falling back to 'default' falling
  -- back to the same disclosed safe default (round_half_up at the currency's own
  -- minor_unit_precision) -- never a second, competing rounding mechanism.
  for v_rounding_row in select * from app.resolve_finance_config('finance_rounding', p_tenant_id) loop
    if v_rounding_row.items ? 'warehouse_billing' then
      v_mode := coalesce(v_rounding_row.items -> 'warehouse_billing' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'warehouse_billing' ->> 'precision')::integer, v_precision);
      v_order := coalesce(v_rounding_row.items -> 'warehouse_billing' ->> 'order', v_order);
    elsif v_rounding_row.items ? 'default' then
      v_mode := coalesce(v_rounding_row.items -> 'default' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'default' ->> 'precision')::integer, v_precision);
      v_order := coalesce(v_rounding_row.items -> 'default' ->> 'order', v_order);
    end if;
  end loop;

  v_base_amount := app.apply_finance_rounding(v_base_amount, v_precision, v_mode);

  if p_tax_code is not null then
    v_tax := app.calculate_finance_tax(p_tenant_id, p_tax_code, v_base_amount, p_activity_date::date, p_actor_auth_user_id);
    v_tax_amount := (v_tax ->> 'taxAmount')::numeric;
    v_tax_rule_version_id := (v_tax ->> 'ruleVersionId')::uuid;
  else
    v_tax_amount := 0;
  end if;

  v_total_amount := v_base_amount + coalesce(v_tax_amount, 0);

  v_explanation := jsonb_build_object(
    'rateBasis', p_rate.rate_basis,
    'unitRate', case when p_rate.rate_basis in ('flat', 'per_unit', 'time_basis') then p_rate.unit_rate else null end,
    'tierSchedule', case when p_rate.rate_basis = 'tiered' then p_rate.tier_schedule else null end,
    'quantity', p_quantity,
    'uomCode', p_uom_code,
    'rateUomCode', p_rate.rate_uom_code,
    'uomConversionApplied', v_conversion_applied,
    'convertedQuantity', case when v_conversion_applied then v_converted_quantity else null end,
    'minimumAmount', p_rate.minimum_amount,
    'minimumAmountApplied', v_floor_applied,
    'roundingMode', v_mode,
    'roundingPrecision', v_precision,
    'roundingOrder', v_order,
    'tax', case when p_tax_code is not null then v_tax else jsonb_build_object('applied', false) end
  );

  return jsonb_build_object(
    'contractId', p_rate.contract_id,
    'rateComponentId', p_rate.id,
    'baseAmount', v_base_amount,
    'taxCode', p_tax_code,
    'taxAmount', coalesce(v_tax_amount, 0),
    'taxRuleVersionId', v_tax_rule_version_id,
    'totalAmount', v_total_amount,
    'currency', p_rate.currency,
    'roundingMode', v_mode,
    'calculationExplanation', v_explanation
  );
end;
$$;

comment on function app.compute_warehouse_billing_breakdown is
  'ATW-022: the ONE real calculation implementation -- rate_basis dispatch (flat/per_unit/tiered/time_basis), UOM conversion (app.convert_uom_quantity, ATW-011A), minimum_amount floor, rounding (app.apply_finance_rounding, FIN-194), tax (app.calculate_finance_tax, FIN-195). Called by app.calculate_warehouse_billing_event, app.recalculate_warehouse_billing_event and app.preview_warehouse_billing_calculation -- never duplicated divergently. Internal only, no grant (see migration header).';

-- ===========================================================================
-- 5. Rate configuration (COM:Edit tier).
-- ===========================================================================

create function app.create_warehouse_billing_rate_component(
  p_contract_id uuid,
  p_warehouse_id uuid,
  p_activity_type text,
  p_rate_basis text,
  p_rate_uom_code text,
  p_unit_rate numeric,
  p_minimum_amount numeric,
  p_currency text,
  p_tier_schedule jsonb,
  p_time_basis_unit text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_rate_components
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_contract app.customer_contracts;
  v_warehouse app.warehouses;
  v_component app.warehouse_billing_rate_components;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  -- COM:Edit only -- no separate record-scope check, matching app.customer_contracts'
  -- own real mutation precedent directly (see this migration's own header, correction 4).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_contract.status <> 'draft' then
    raise exception 'rate_component_requires_draft_contract: contract % is % -- rate components may only be added while the contract is draft', p_contract_id, v_contract.status
      using errcode = 'check_violation';
  end if;

  if p_warehouse_id is not null then
    select * into v_warehouse from app.warehouses where id = p_warehouse_id;
    if not found or v_warehouse.tenant_id <> v_contract.tenant_id then
      raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, v_contract.tenant_id using errcode = 'no_data_found';
    end if;
  end if;

  if p_activity_type not in ('storage', 'receiving', 'handling', 'putaway', 'pick', 'pack', 'outbound', 'value_added') then
    raise exception 'invalid_activity_type: % is not a recognized activity type', p_activity_type using errcode = 'check_violation';
  end if;
  if p_rate_basis not in ('flat', 'per_unit', 'tiered', 'time_basis') then
    raise exception 'invalid_rate_basis: % is not a recognized rate basis', p_rate_basis using errcode = 'check_violation';
  end if;
  if p_unit_rate is null or p_unit_rate < 0 then
    raise exception 'invalid_unit_rate: unit_rate must be non-negative' using errcode = 'check_violation';
  end if;
  if p_minimum_amount is not null and p_minimum_amount < 0 then
    raise exception 'invalid_minimum_amount: minimum_amount must be non-negative' using errcode = 'check_violation';
  end if;
  if not app.validate_currency_code(p_currency) then
    raise exception 'invalid_currency: % is not a registered, active currency', p_currency using errcode = 'check_violation';
  end if;

  if p_rate_basis = 'flat' then
    if p_rate_uom_code is not null then
      raise exception 'invalid_rate_uom_for_basis: rate_uom_code must be null for rate_basis=flat' using errcode = 'check_violation';
    end if;
  else
    if p_rate_uom_code is null then
      raise exception 'invalid_rate_uom_for_basis: rate_uom_code is required for rate_basis=%', p_rate_basis using errcode = 'check_violation';
    end if;
    if not app.validate_uom_code(p_rate_uom_code) then
      raise exception 'invalid_uom_code: % is not a registered UOM code', p_rate_uom_code using errcode = 'check_violation';
    end if;
  end if;

  if p_rate_basis = 'tiered' then
    if not app.validate_warehouse_billing_tier_schedule(p_tier_schedule) then
      raise exception 'invalid_tier_schedule: tier_schedule must be a non-empty array of {threshold, rate} objects with strictly ascending threshold' using errcode = 'check_violation';
    end if;
  elsif p_tier_schedule is not null then
    raise exception 'invalid_tier_schedule: tier_schedule is only meaningful for rate_basis=tiered' using errcode = 'check_violation';
  end if;

  if p_rate_basis = 'time_basis' then
    if p_time_basis_unit is null or length(trim(p_time_basis_unit)) = 0 then
      raise exception 'invalid_time_basis_unit: time_basis_unit is required for rate_basis=time_basis' using errcode = 'check_violation';
    end if;
  elsif p_time_basis_unit is not null then
    raise exception 'invalid_time_basis_unit: time_basis_unit is only meaningful for rate_basis=time_basis' using errcode = 'check_violation';
  end if;

  begin
    insert into app.warehouse_billing_rate_components (
      tenant_id, contract_id, warehouse_id, activity_type, rate_basis, rate_uom_code, unit_rate, minimum_amount, currency,
      tier_schedule, time_basis_unit, created_by
    ) values (
      v_contract.tenant_id, p_contract_id, p_warehouse_id, p_activity_type, p_rate_basis, p_rate_uom_code, p_unit_rate, p_minimum_amount, p_currency,
      p_tier_schedule, p_time_basis_unit, p_actor_label
    )
    returning * into v_component;
  exception
    when unique_violation then
      raise exception 'rate_component_scope_conflict: contract % already has a % rate component for % (warehouse %)', p_contract_id, p_activity_type, p_activity_type, coalesce(p_warehouse_id::text, 'tenant-wide')
        using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_contract.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_warehouse_billing_rate_component',
    'app.warehouse_billing_rate_components', v_component.id, 'success', null, null,
    jsonb_build_object('contract_id', p_contract_id, 'activity_type', p_activity_type, 'rate_basis', p_rate_basis)
  );

  return v_component;
end;
$$;

comment on function app.create_warehouse_billing_rate_component is
  'ATW-022: COM:Edit-gated, requires the owning contract to be status=draft (mirrors app.add_customer_contract_price_component''s own draft-only precedent, COM-156). Rejects a malformed/non-ascending tier_schedule as invalid_tier_schedule. No separate set-status RPC -- rate components live and die with the contract''s own publish/retire lifecycle.';

-- ===========================================================================
-- 6. Event lifecycle (OPS tier).
-- ===========================================================================

create function app.get_effective_warehouse_billing_rate(
  p_tenant_id uuid,
  p_account_id uuid,
  p_warehouse_id uuid,
  p_activity_type text,
  p_as_of timestamptz,
  p_actor_auth_user_id uuid
)
returns app.warehouse_billing_rate_components
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rate app.warehouse_billing_rate_components;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, p_warehouse_id, p_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot resolve a rate under warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, p_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for account %', p_actor_auth_user_id, p_account_id using errcode = 'insufficient_privilege';
  end if;

  select rc.* into v_rate
  from app.warehouse_billing_rate_components rc
  join app.customer_contracts cc on cc.id = rc.contract_id
  where cc.tenant_id = p_tenant_id
    and cc.account_id = p_account_id
    and cc.status = 'published'
    and cc.effective_from <= p_as_of
    and (cc.effective_to is null or cc.effective_to > p_as_of)
    and rc.activity_type = p_activity_type
    and (rc.warehouse_id = p_warehouse_id or rc.warehouse_id is null)
  order by rc.warehouse_id nulls last
  limit 1;

  if not found then
    raise exception 'no_effective_rate: no published contract rate component covers account %, activity %, warehouse %, as_of %', p_account_id, p_activity_type, p_warehouse_id, p_as_of
      using errcode = 'no_data_found';
  end if;

  return v_rate;
end;
$$;

comment on function app.get_effective_warehouse_billing_rate is
  'ATW-022: mirrors app.get_effective_customer_price''s own matching logic (COM-156) -- a warehouse-specific rate wins over a tenant-wide-null one when both exist (order by warehouse_id nulls last). Raises no_effective_rate on zero match, never a silent zero/wrong rate.';

create function app.capture_warehouse_billing_event(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_owner_account_id uuid,
  p_activity_type text,
  p_source_type text,
  p_source_id uuid,
  p_quantity numeric,
  p_uom_code text,
  p_activity_date timestamptz,
  p_idempotency_key text,
  p_correction_reason text default null,
  p_actor_auth_user_id uuid default null,
  p_actor_label text default null
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_existing app.warehouse_billing_events;
  v_existing_source app.warehouse_billing_events;
  v_event app.warehouse_billing_events;
  v_required_action text;
  v_source_version integer;
  v_source_tenant_id uuid;
  v_source_warehouse_id uuid;
  v_source_owner_account_id uuid;
  v_receipt_line app.wms_receipt_lines;
  v_receipt_session app.wms_receipt_sessions;
  v_putaway_task app.wms_putaway_tasks;
  v_pick_task app.wms_pick_tasks;
  v_package app.wms_packages;
  v_eligibility_event app.wms_billing_eligibility_events;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to capture a warehouse billing event' using errcode = 'check_violation';
  end if;
  if p_source_type not in ('wms_receipt_line', 'wms_putaway_confirmation', 'wms_pick_task_confirmation', 'wms_package_confirmation', 'wms_billing_eligibility_event', 'manual') then
    raise exception 'invalid_source_type: % is not a recognized source type', p_source_type using errcode = 'check_violation';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_activity_date is null then
    raise exception 'invalid_activity_date: activity_date is required' using errcode = 'check_violation';
  end if;

  select * into v_warehouse from app.warehouses where id = p_warehouse_id;
  if not found or v_warehouse.tenant_id <> p_tenant_id then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  -- source_type='manual' requires OPS:Override (a disclosed, governed exception path
  -- for storage/value-added activity with no backing operational table this
  -- checkpoint) -- every real dispatch value requires only OPS:Create.
  v_required_action := case when p_source_type = 'manual' then 'Override' else 'Create' end;
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', v_required_action);
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:% (%) for tenant %', p_actor_auth_user_id, v_required_action, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, p_warehouse_id, p_owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot capture a billing event under warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before, and ALWAYS validating the found row's own real target matches the current
  -- call's target before treating it as a safe replay (the ATW-020/021 lesson).
  -- warehouse_id/owner_account_id are REQUIRED in this match -- without them, a caller
  -- who is authorized only for their OWN warehouse/owner (checked above via
  -- wms_pick_record_scope_ok/p_owner_account_id) could reuse another target's real
  -- idempotency_key/source_type/source_id/activity_type combination and have this
  -- short-circuit hand back that OTHER target's full row, including its calculated
  -- financial amounts -- an authorization bypass, not a safe replay.
  select * into v_existing from app.warehouse_billing_events where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.source_type = p_source_type and v_existing.source_id is not distinct from p_source_id and v_existing.activity_type = p_activity_type
      and v_existing.warehouse_id = p_warehouse_id and v_existing.owner_account_id = p_owner_account_id then
      return v_existing;
    end if;
    raise exception 'idempotency_key_conflict: idempotency key % was already used for a different capture (source_type=%, source_id=%, activity_type=%, warehouse_id=%, owner_account_id=%)', p_idempotency_key, v_existing.source_type, v_existing.source_id, v_existing.activity_type, v_existing.warehouse_id, v_existing.owner_account_id
      using errcode = 'unique_violation';
  end if;

  if p_activity_type not in ('storage', 'receiving', 'handling', 'putaway', 'pick', 'pack', 'outbound', 'value_added') then
    raise exception 'invalid_activity_type: % is not a recognized activity type', p_activity_type using errcode = 'check_violation';
  end if;
  if not app.validate_uom_code(p_uom_code) then
    raise exception 'invalid_uom_code: % is not a registered UOM code', p_uom_code using errcode = 'check_violation';
  end if;

  if p_source_type = 'manual' then
    if p_correction_reason is null or length(trim(p_correction_reason)) = 0 then
      raise exception 'manual_reason_required: a non-empty reason is required to manually capture a warehouse billing event with no backing operational source' using errcode = 'check_violation';
    end if;
    v_source_version := null;
  else
    if p_source_id is null then
      raise exception 'source_id_required: source_id is required for source_type %', p_source_type using errcode = 'check_violation';
    end if;

    if p_source_type = 'wms_receipt_line' then
      select * into v_receipt_line from app.wms_receipt_lines where id = p_source_id;
      if not found then
        raise exception 'source_not_found: wms_receipt_line % not found', p_source_id using errcode = 'no_data_found';
      end if;
      if v_receipt_line.status <> 'committed' then
        raise exception 'source_not_eligible: wms_receipt_line % is % -- only a committed receipt line is billable', p_source_id, v_receipt_line.status using errcode = 'check_violation';
      end if;
      select * into v_receipt_session from app.wms_receipt_sessions where id = v_receipt_line.receipt_session_id;
      v_source_tenant_id := v_receipt_line.tenant_id;
      v_source_warehouse_id := v_receipt_session.warehouse_id;
      v_source_owner_account_id := v_receipt_line.owner_account_id;
      v_source_version := v_receipt_line.record_version;

    elsif p_source_type = 'wms_putaway_confirmation' then
      select * into v_putaway_task from app.wms_putaway_tasks where id = p_source_id;
      if not found then
        raise exception 'source_not_found: wms_putaway_tasks % not found', p_source_id using errcode = 'no_data_found';
      end if;
      if v_putaway_task.status <> 'confirmed' then
        raise exception 'source_not_eligible: wms_putaway_tasks % is % -- only a confirmed putaway task is billable', p_source_id, v_putaway_task.status using errcode = 'check_violation';
      end if;
      v_source_tenant_id := v_putaway_task.tenant_id;
      v_source_warehouse_id := v_putaway_task.warehouse_id;
      v_source_owner_account_id := v_putaway_task.owner_account_id;
      v_source_version := v_putaway_task.record_version;

    elsif p_source_type = 'wms_pick_task_confirmation' then
      select * into v_pick_task from app.wms_pick_tasks where id = p_source_id;
      if not found then
        raise exception 'source_not_found: wms_pick_tasks % not found', p_source_id using errcode = 'no_data_found';
      end if;
      if v_pick_task.status not in ('picked', 'short') then
        raise exception 'source_not_eligible: wms_pick_tasks % is % -- only a picked or short pick task is billable', p_source_id, v_pick_task.status using errcode = 'check_violation';
      end if;
      v_source_tenant_id := v_pick_task.tenant_id;
      v_source_warehouse_id := v_pick_task.warehouse_id;
      v_source_owner_account_id := v_pick_task.owner_account_id;
      v_source_version := v_pick_task.record_version;

    elsif p_source_type = 'wms_package_confirmation' then
      select * into v_package from app.wms_packages where id = p_source_id;
      if not found then
        raise exception 'source_not_found: wms_packages % not found', p_source_id using errcode = 'no_data_found';
      end if;
      if v_package.status <> 'confirmed' then
        raise exception 'source_not_eligible: wms_packages % is % -- only a confirmed package is billable', p_source_id, v_package.status using errcode = 'check_violation';
      end if;
      v_source_tenant_id := v_package.tenant_id;
      v_source_warehouse_id := v_package.warehouse_id;
      v_source_owner_account_id := v_package.owner_account_id;
      v_source_version := v_package.record_version;

    elsif p_source_type = 'wms_billing_eligibility_event' then
      select * into v_eligibility_event from app.wms_billing_eligibility_events where id = p_source_id;
      if not found then
        raise exception 'source_not_found: wms_billing_eligibility_events % not found', p_source_id using errcode = 'no_data_found';
      end if;
      v_source_tenant_id := v_eligibility_event.tenant_id;
      v_source_warehouse_id := v_eligibility_event.warehouse_id;
      v_source_owner_account_id := v_eligibility_event.owner_account_id;
      v_source_version := 1; -- append-only, no record_version column -- see migration header correction 3.
    end if;

    if v_source_tenant_id <> p_tenant_id or v_source_warehouse_id <> p_warehouse_id or v_source_owner_account_id <> p_owner_account_id then
      raise exception 'source_mismatch: the source row''s own tenant/warehouse/owner does not match the captured tenant/warehouse/owner' using errcode = 'check_violation';
    end if;

    select * into v_existing_source from app.warehouse_billing_events
      where tenant_id = p_tenant_id and source_type = p_source_type and source_id = p_source_id and source_version = v_source_version
        and corrects_event_id is null and reverses_event_id is null;
    if found then
      raise exception 'source_already_captured: % % (version %) already has an active billing event %', p_source_type, p_source_id, v_source_version, v_existing_source.id
        using errcode = 'check_violation';
    end if;
  end if;

  begin
    insert into app.warehouse_billing_events (
      tenant_id, warehouse_id, owner_account_id, activity_type, source_type, source_id, source_version,
      activity_date, quantity, uom_code, idempotency_key, created_by
    ) values (
      p_tenant_id, p_warehouse_id, p_owner_account_id, p_activity_type, p_source_type, p_source_id, v_source_version,
      p_activity_date, p_quantity, p_uom_code, p_idempotency_key, p_actor_label
    )
    returning * into v_event;
  exception
    when unique_violation then
      select * into v_existing from app.warehouse_billing_events where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        if v_existing.source_type = p_source_type and v_existing.source_id is not distinct from p_source_id and v_existing.activity_type = p_activity_type
          and v_existing.warehouse_id = p_warehouse_id and v_existing.owner_account_id = p_owner_account_id then
          return v_existing;
        end if;
        raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent capture', p_idempotency_key using errcode = 'unique_violation';
      end if;
      raise exception 'source_already_captured: % % (version %) was captured concurrently by another request', p_source_type, p_source_id, v_source_version using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'capture_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', p_correction_reason, null,
    jsonb_build_object('activity_type', p_activity_type, 'source_type', p_source_type, 'source_id', p_source_id, 'source_version', v_source_version)
  );

  return v_event;
end;
$$;

comment on function app.capture_warehouse_billing_event is
  'ATW-022: OPS:Create for a real dispatch source_type, OPS:Override for manual. Idempotent on (tenant_id, idempotency_key), validating the found row''s own source_type/source_id/activity_type AND warehouse_id/owner_account_id (the two RLS/authorization-scoping fields) before treating it as a safe replay -- anything short of all five raises idempotency_key_conflict, never silently returning a different target''s row. Enforces "at most one active event per source" (source_already_captured on a genuine duplicate). p_correction_reason is unused for a normal capture except as the manual-entry justification; it also documents why app.correct_warehouse_billing_event/app.reverse_warehouse_billing_event do NOT call this function directly (see migration header).';

create function app.calculate_warehouse_billing_event(
  p_event_id uuid,
  p_expected_version integer,
  p_tax_code text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
  v_rate app.warehouse_billing_rate_components;
  v_calc jsonb;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'draft' then
    raise exception 'already_calculated: billing event % is % -- use app.recalculate_warehouse_billing_event instead', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  -- as_of = the event's own activity_date, never now() (Prompt 241's own explicit rule).
  v_rate := app.get_effective_warehouse_billing_rate(v_event.tenant_id, v_event.owner_account_id, v_event.warehouse_id, v_event.activity_type, v_event.activity_date, p_actor_auth_user_id);
  v_calc := app.compute_warehouse_billing_breakdown(v_event.tenant_id, v_rate, v_event.quantity, v_event.uom_code, v_event.activity_date, p_tax_code, p_actor_auth_user_id);

  update app.warehouse_billing_events set
    contract_id = v_rate.contract_id,
    rate_component_id = v_rate.id,
    base_amount = (v_calc ->> 'baseAmount')::numeric,
    tax_code = p_tax_code,
    tax_rule_version_id = (v_calc ->> 'taxRuleVersionId')::uuid,
    tax_amount = (v_calc ->> 'taxAmount')::numeric,
    total_amount = (v_calc ->> 'totalAmount')::numeric,
    currency = v_calc ->> 'currency',
    rounding_mode = v_calc ->> 'roundingMode',
    calculation_explanation = v_calc -> 'calculationExplanation',
    status = 'pending_review'
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null,
    jsonb_build_object('total_amount', v_event.total_amount, 'contract_id', v_event.contract_id, 'rate_component_id', v_event.rate_component_id)
  );

  return v_event;
end;
$$;

comment on function app.calculate_warehouse_billing_event is
  'ATW-022: OPS:Edit + record/owner-scope. status must be draft (already_calculated otherwise). Resolves the effective rate as of the event''s own activity_date, then app.compute_warehouse_billing_breakdown for the one real arithmetic implementation. status -> pending_review.';

create function app.recalculate_warehouse_billing_event(
  p_event_id uuid,
  p_expected_version integer,
  p_reason text,
  p_tax_code text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
  v_rate app.warehouse_billing_rate_components;
  v_calc jsonb;
  v_before_total numeric;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- A governed re-calculation -- OPS:Override, requiring a reason (Prompt 241 section
  -- 14's own "recalculate-with-version" distinct API surface).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot edit billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status not in ('pending_review', 'reviewed') then
    raise exception 'invalid_transition: billing event % is % -- only pending_review or reviewed may be recalculated (use correct/reverse for approved/handed-off events)', p_event_id, v_event.status
      using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to recalculate a billing event' using errcode = 'check_violation';
  end if;

  v_before_total := v_event.total_amount;

  v_rate := app.get_effective_warehouse_billing_rate(v_event.tenant_id, v_event.owner_account_id, v_event.warehouse_id, v_event.activity_type, v_event.activity_date, p_actor_auth_user_id);
  v_calc := app.compute_warehouse_billing_breakdown(v_event.tenant_id, v_rate, v_event.quantity, v_event.uom_code, v_event.activity_date, p_tax_code, p_actor_auth_user_id);

  -- Re-runs the IDENTICAL calculation logic app.calculate_warehouse_billing_event uses
  -- (the shared internal function), IN PLACE on the same row -- legitimate pre-
  -- approval iteration, not a "silent amount rewrite after handoff" (nothing has been
  -- approved/handed off yet at pending_review/reviewed). A recalculation always
  -- resets any prior review to pending_review -- the reviewer must look again.
  update app.warehouse_billing_events set
    contract_id = v_rate.contract_id,
    rate_component_id = v_rate.id,
    base_amount = (v_calc ->> 'baseAmount')::numeric,
    tax_code = p_tax_code,
    tax_rule_version_id = (v_calc ->> 'taxRuleVersionId')::uuid,
    tax_amount = (v_calc ->> 'taxAmount')::numeric,
    total_amount = (v_calc ->> 'totalAmount')::numeric,
    currency = v_calc ->> 'currency',
    rounding_mode = v_calc ->> 'roundingMode',
    calculation_explanation = v_calc -> 'calculationExplanation',
    status = 'pending_review'
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'recalculate_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', p_reason,
    jsonb_build_object('total_amount', v_before_total), jsonb_build_object('total_amount', v_event.total_amount)
  );

  return v_event;
end;
$$;

comment on function app.recalculate_warehouse_billing_event is
  'ATW-022: OPS:Override, reason mandatory. status must be pending_review or reviewed (never approved/handed_off/terminal -- use correct/reverse for those). Re-runs app.compute_warehouse_billing_breakdown IN PLACE on the same row. Always resets to pending_review -- a recalculation invalidates a prior review.';

create function app.hold_warehouse_billing_event(
  p_event_id uuid,
  p_reason text,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot hold billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status not in ('pending_review', 'reviewed') then
    raise exception 'invalid_transition: billing event % is % -- only pending_review or reviewed may be held', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to hold a billing event' using errcode = 'check_violation';
  end if;

  update app.warehouse_billing_events set status = 'on_hold', hold_reason = p_reason where id = p_event_id and record_version = p_expected_version returning * into v_event;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', p_reason, null, null
  );

  return v_event;
end;
$$;

create function app.release_warehouse_billing_event_hold(
  p_event_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot release billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'on_hold' then
    raise exception 'invalid_transition: billing event % is % -- only on_hold may be released', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  -- Always back to pending_review, never directly to reviewed/approved -- a held
  -- event must be looked at again from the start.
  update app.warehouse_billing_events set status = 'pending_review' where id = p_event_id and record_version = p_expected_version returning * into v_event;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'release_warehouse_billing_event_hold',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$$;

create function app.review_warehouse_billing_event(
  p_event_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot review billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'pending_review' then
    raise exception 'invalid_transition: billing event % is % -- only pending_review may be reviewed', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;

  update app.warehouse_billing_events set
    status = 'reviewed', reviewed_by_auth_user_id = p_actor_auth_user_id, reviewed_by_label = p_actor_label, reviewed_at = now()
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'review_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$$;

create function app.approve_warehouse_billing_event(
  p_event_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- A governed release-to-Finance decision -- OPS:Override.
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot approve billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  if v_event.status <> 'reviewed' then
    raise exception 'invalid_transition: billing event % is % -- only reviewed may be approved', p_event_id, v_event.status using errcode = 'check_violation';
  end if;
  if v_event.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_event_id, p_expected_version, v_event.record_version using errcode = 'check_violation';
  end if;
  -- Segregation of duties (mirrors ATW-020's own established self_approval_not_allowed
  -- pattern): the same identity that reviewed an event may not also approve it.
  if v_event.reviewed_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % reviewed billing event % and may not also approve it', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  update app.warehouse_billing_events set
    status = 'approved', approved_by_auth_user_id = p_actor_auth_user_id, approved_by_label = p_actor_label, approved_at = now()
  where id = p_event_id and record_version = p_expected_version
  returning * into v_event;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_warehouse_billing_event',
    'app.warehouse_billing_events', v_event.id, 'success', null, null, null
  );

  return v_event;
end;
$$;

create function app.handoff_warehouse_billing_event(
  p_event_id uuid,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_handoffs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
  v_existing app.warehouse_billing_handoffs;
  v_handoff app.warehouse_billing_handoffs;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to hand off a billing event' using errcode = 'check_violation';
  end if;

  select * into v_event from app.warehouse_billing_events where id = p_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  -- Release-authority already spent at approve -- handoff itself is mechanical
  -- (mirrors OPS-181's own identical Override-then-Edit tiering between
  -- override_billing_readiness and handoff_billing_readiness).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot hand off billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before, and ALWAYS validating the found handoff's own real target (billing_event_id)
  -- matches the current call's target before treating it as a safe replay (the
  -- ATW-020/021 lesson, again -- the third RPC in this migration where it applies).
  select * into v_existing from app.warehouse_billing_handoffs where tenant_id = v_event.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.billing_event_id = p_event_id then
      return v_existing;
    end if;
    raise exception 'idempotency_key_conflict: idempotency key % was already used for a different billing event''s handoff', p_idempotency_key using errcode = 'unique_violation';
  end if;

  if v_event.status <> 'approved' then
    raise exception 'invalid_transition: billing event % is % -- only approved may be handed off', p_event_id, v_event.status using errcode = 'check_violation';
  end if;

  begin
    insert into app.warehouse_billing_handoffs (tenant_id, billing_event_id, idempotency_key, handed_off_by_auth_user_id, handed_off_by_label)
    values (v_event.tenant_id, p_event_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label)
    returning * into v_handoff;
  exception
    when unique_violation then
      select * into v_existing from app.warehouse_billing_handoffs where tenant_id = v_event.tenant_id and idempotency_key = p_idempotency_key;
      if found and v_existing.billing_event_id = p_event_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: idempotency key % was already used by a different, concurrent handoff', p_idempotency_key using errcode = 'unique_violation';
  end;

  update app.warehouse_billing_events set status = 'handed_off' where id = p_event_id;

  perform app.capture_audit_event(
    v_event.tenant_id, p_actor_auth_user_id, p_actor_label, 'handoff_warehouse_billing_event',
    'app.warehouse_billing_handoffs', v_handoff.id, 'success', null, null, jsonb_build_object('billing_event_id', p_event_id)
  );

  return v_handoff;
end;
$$;

comment on function app.handoff_warehouse_billing_event is
  'ATW-022: OPS:Edit. status must be approved. Idempotent on (tenant_id, idempotency_key), validating the found handoff''s own billing_event_id matches before returning it as a safe replay -- never silently returns a different event''s handoff.';

create function app.record_warehouse_billing_reconciliation_outcome(
  p_handoff_id uuid,
  p_status text,
  p_note text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_handoffs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.warehouse_billing_handoffs;
begin
  if p_actor_label is null or length(trim(p_actor_label)) = 0 then
    raise exception 'invalid_actor_label: an actor label is required to record a reconciliation outcome' using errcode = 'check_violation';
  end if;
  if p_status not in ('reconciled', 'rejected') then
    raise exception 'invalid_status: % is not a recognized reconciliation outcome', p_status using errcode = 'check_violation';
  end if;
  if p_note is null or length(trim(p_note)) = 0 then
    raise exception 'invalid_note: a non-empty reconciliation note is required' using errcode = 'check_violation';
  end if;

  select * into v_handoff from app.warehouse_billing_handoffs where id = p_handoff_id for update;
  if not found then
    raise exception 'warehouse_billing_handoff_not_found: %', p_handoff_id using errcode = 'no_data_found';
  end if;

  if v_handoff.reconciliation_status is not null then
    if v_handoff.reconciliation_status = p_status then
      return v_handoff;
    end if;
    raise exception 'reconciliation_outcome_conflict: handoff % already has reconciliation_status % and cannot be changed to %', p_handoff_id, v_handoff.reconciliation_status, p_status
      using errcode = 'check_violation';
  end if;

  update app.warehouse_billing_handoffs set
    reconciliation_status = p_status, reconciliation_note = p_note, reconciled_at = now(), updated_at = now()
  where id = p_handoff_id
  returning * into v_handoff;

  perform app.capture_audit_event(
    v_handoff.tenant_id, p_actor_auth_user_id, p_actor_label, 'record_warehouse_billing_reconciliation_outcome',
    'app.warehouse_billing_handoffs', v_handoff.id, 'success', p_note, null, jsonb_build_object('reconciliation_status', p_status)
  );

  return v_handoff;
end;
$$;

comment on function app.record_warehouse_billing_reconciliation_outcome is
  'ATW-022: service_role ONLY, no authenticated grant at all -- a Finance-side worker callback, mirroring app.record_label_print_outcome''s exact precedent (ATW-021): a real, callable interface with nothing calling it yet, since no live Finance consumer exists in this repository. Idempotent on a same-outcome replay; rejects a conflicting second outcome (reconciliation_outcome_conflict) on an already-reconciled/rejected row.';

create function app.correct_warehouse_billing_event(
  p_original_event_id uuid,
  p_expected_version integer,
  p_new_quantity numeric,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_original app.warehouse_billing_events;
  v_existing app.warehouse_billing_events;
  v_new app.warehouse_billing_events;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to correct a billing event' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to correct a billing event' using errcode = 'check_violation';
  end if;
  if p_new_quantity is null or p_new_quantity <= 0 then
    raise exception 'invalid_quantity: the corrected quantity must be positive' using errcode = 'check_violation';
  end if;

  select * into v_original from app.warehouse_billing_events where id = p_original_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_original_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_original.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_original.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_original.warehouse_id, v_original.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot correct billing event %', p_actor_auth_user_id, p_original_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_original.tenant_id, v_original.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_original_event_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before, and ALWAYS validating the found row's own real corrects_event_id matches.
  select * into v_existing from app.warehouse_billing_events where tenant_id = v_original.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.corrects_event_id = p_original_event_id then
      return v_existing;
    end if;
    raise exception 'idempotency_key_conflict: idempotency key % was already used for a different correction', p_idempotency_key using errcode = 'unique_violation';
  end if;

  if v_original.status in ('corrected', 'reversed') then
    raise exception 'already_corrected: billing event % is already %', p_original_event_id, v_original.status using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.warehouse_billing_events where corrects_event_id = p_original_event_id) then
    raise exception 'already_corrected: billing event % already has a correcting event', p_original_event_id using errcode = 'check_violation';
  end if;
  -- The established optimistic-concurrency contract every other lifecycle-mutating RPC
  -- in this migration applies (bug class b) -- protects against a client acting on
  -- stale business context that the already_corrected checks above do not cover (e.g.
  -- correcting an event the client believed was still plain approved when it has since
  -- been placed on_hold by another actor in the interim).
  if v_original.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_original_event_id, p_expected_version, v_original.record_version using errcode = 'check_violation';
  end if;

  -- Callable regardless of the original's own status (including handed_off --
  -- correcting an already-handed-off event is the whole point of this RPC). A
  -- correction is a fresh financial fact -- the new row still needs its own real
  -- calculate/review/approve/handoff cycle, so it starts genuinely draft.
  begin
    insert into app.warehouse_billing_events (
      tenant_id, warehouse_id, owner_account_id, activity_type, source_type, source_id, source_version,
      uom_code, activity_date, contract_id, rate_component_id, quantity, status, corrects_event_id, correction_reason, idempotency_key, created_by
    ) values (
      v_original.tenant_id, v_original.warehouse_id, v_original.owner_account_id, v_original.activity_type, v_original.source_type, v_original.source_id, v_original.source_version,
      v_original.uom_code, v_original.activity_date, v_original.contract_id, v_original.rate_component_id, p_new_quantity, 'draft', p_original_event_id, p_reason, p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      select * into v_existing from app.warehouse_billing_events where tenant_id = v_original.tenant_id and idempotency_key = p_idempotency_key;
      if found and v_existing.corrects_event_id = p_original_event_id then
        return v_existing;
      end if;
      -- The idempotency_key may be genuinely fresh here -- the unique_violation can
      -- also come from the new warehouse_billing_events_one_correction_per_original_idx
      -- (a concurrent correction of the SAME original under a different key), mirroring
      -- app.reverse_warehouse_billing_event's own identical fallback exactly.
      raise exception 'already_corrected: billing event % already has a correcting event (concurrent request)', p_original_event_id using errcode = 'check_violation';
  end;

  -- A lifecycle marker only -- the ORIGINAL's own base_amount/tax_amount/total_amount/
  -- calculation_explanation are never touched (proving no in-place rewrite).
  update app.warehouse_billing_events set status = 'corrected' where id = p_original_event_id and record_version = p_expected_version;

  perform app.capture_audit_event(
    v_original.tenant_id, p_actor_auth_user_id, p_actor_label, 'correct_warehouse_billing_event',
    'app.warehouse_billing_events', v_new.id, 'success', p_reason,
    jsonb_build_object('original_event_id', p_original_event_id, 'original_quantity', v_original.quantity),
    jsonb_build_object('new_quantity', p_new_quantity)
  );

  return v_new;
end;
$$;

comment on function app.correct_warehouse_billing_event is
  'ATW-022: OPS:Override. Callable regardless of the original''s own status (including handed_off), rejected already_corrected if the original is already corrected/reversed or already has a correcting child, or stale_version on a version mismatch (the same optimistic-concurrency contract every other lifecycle RPC in this migration applies). Creates a NEW draft event (corrects_event_id set) needing its own full calculate/review/approve/handoff cycle -- the original''s status flips to corrected, its own calculated amounts untouched. Enforced by a real partial unique index: at most one correction per original. Does NOT compose app.capture_warehouse_billing_event -- see migration header.';

create function app.reverse_warehouse_billing_event(
  p_original_event_id uuid,
  p_expected_version integer,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.warehouse_billing_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_original app.warehouse_billing_events;
  v_existing app.warehouse_billing_events;
  v_new app.warehouse_billing_events;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to reverse a billing event' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'invalid_reason: a non-empty reason is required to reverse a billing event' using errcode = 'check_violation';
  end if;

  select * into v_original from app.warehouse_billing_events where id = p_original_event_id for update;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_original_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_original.tenant_id, 'OPS', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_original.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_original.warehouse_id, v_original.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot reverse billing event %', p_actor_auth_user_id, p_original_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_original.tenant_id, v_original.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for billing event %', p_actor_auth_user_id, p_original_event_id using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent replay short-circuit -- only after authority is confirmed above, never
  -- before, and ALWAYS validating the found row's own real reverses_event_id matches.
  select * into v_existing from app.warehouse_billing_events where tenant_id = v_original.tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.reverses_event_id = p_original_event_id then
      return v_existing;
    end if;
    raise exception 'idempotency_key_conflict: idempotency key % was already used for a different reversal', p_idempotency_key using errcode = 'unique_violation';
  end if;

  if v_original.status not in ('approved', 'handed_off') then
    raise exception 'invalid_transition: billing event % is % -- only an approved or handed-off event may be reversed', p_original_event_id, v_original.status using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.warehouse_billing_events where reverses_event_id = p_original_event_id) then
    raise exception 'already_reversed: billing event % already has a reversing event', p_original_event_id using errcode = 'check_violation';
  end if;
  -- The established optimistic-concurrency contract every other lifecycle-mutating RPC
  -- in this migration applies (bug class b) -- see app.correct_warehouse_billing_event's
  -- own identical rationale.
  if v_original.record_version <> p_expected_version then
    raise exception 'stale_version: billing event % expected version % but found %', p_original_event_id, p_expected_version, v_original.record_version using errcode = 'check_violation';
  end if;

  -- A reversal does NOT recalculate -- it exactly negates the original's own already-
  -- calculated values. status is inserted as pending_review, not draft: see this
  -- migration's own header design-decision note for why (skips calculate entirely,
  -- proceeds straight through review/approve/handoff, matching Prompt 241's own
  -- described cycle for a reversal and avoiding a structural risk of the negation
  -- being silently overwritten by a later calculate call).
  begin
    insert into app.warehouse_billing_events (
      tenant_id, warehouse_id, owner_account_id, activity_type, source_type, source_id, source_version,
      uom_code, activity_date, contract_id, rate_component_id, quantity,
      base_amount, tax_code, tax_rule_version_id, tax_amount, total_amount, currency, rounding_mode, calculation_explanation,
      status, reverses_event_id, correction_reason, idempotency_key, created_by
    ) values (
      v_original.tenant_id, v_original.warehouse_id, v_original.owner_account_id, v_original.activity_type, v_original.source_type, v_original.source_id, v_original.source_version,
      v_original.uom_code, v_original.activity_date, v_original.contract_id, v_original.rate_component_id, v_original.quantity,
      -v_original.base_amount, v_original.tax_code, v_original.tax_rule_version_id, -coalesce(v_original.tax_amount, 0), -v_original.total_amount, v_original.currency, v_original.rounding_mode,
      jsonb_build_object('reversalOfEventId', v_original.id, 'originalCalculationExplanation', v_original.calculation_explanation),
      'pending_review', p_original_event_id, p_reason, p_idempotency_key, p_actor_label
    )
    returning * into v_new;
  exception
    when unique_violation then
      select * into v_existing from app.warehouse_billing_events where tenant_id = v_original.tenant_id and idempotency_key = p_idempotency_key;
      if found and v_existing.reverses_event_id = p_original_event_id then
        return v_existing;
      end if;
      raise exception 'already_reversed: billing event % already has a reversing event (concurrent request)', p_original_event_id using errcode = 'check_violation';
  end;

  -- A lifecycle marker only -- mirrors app.correct_warehouse_billing_event's own
  -- identical "flip the original's status, never touch its own already-calculated
  -- amount columns" pattern. Without this, the original stays 'approved'/'handed_off'
  -- forever and can be legitimately handed off to Finance a second time after being
  -- reversed (the exact bug this statement closes).
  update app.warehouse_billing_events set status = 'reversed' where id = p_original_event_id and record_version = p_expected_version;

  perform app.capture_audit_event(
    v_original.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_warehouse_billing_event',
    'app.warehouse_billing_events', v_new.id, 'success', p_reason,
    jsonb_build_object('original_event_id', p_original_event_id, 'original_total_amount', v_original.total_amount),
    jsonb_build_object('new_total_amount', v_new.total_amount)
  );

  return v_new;
end;
$$;

comment on function app.reverse_warehouse_billing_event is
  'ATW-022: OPS:Override. Requires the original to be approved or handed_off, or stale_version on a version mismatch (the same optimistic-concurrency contract every other lifecycle RPC in this migration applies). Creates a NEW event whose base_amount/tax_amount/total_amount are the exact negation of the original''s own already-calculated values (never a fresh recalculation), status=pending_review (see migration header), reverses_event_id set. The ORIGINAL''s own status flips to reversed (mirrors app.correct_warehouse_billing_event''s identical corrected-flip; its own calculated amounts untouched) -- a reversed original can never again be legitimately handed off. Enforced by a real partial unique index: at most one reversal per original. Does NOT compose app.capture_warehouse_billing_event -- see migration header.';

-- ===========================================================================
-- 7. Reads. Bounded (p_limit clamped to [1, 200], default 50). Owner-account
--    scoping (app.actor_can_view_owner_scoped_row) applied in addition to
--    tenant-wide RBAC (OPS:View) and warehouse-record-scope.
--
--    Field-masking gate (mirrors COM-156's own app.customer_contract_price_components
--    masking convention directly, per Prompt 241 section 16's own "customer contract/
--    rate/amount fields use strict roles and field policy" requirement): OPS:View
--    alone is enough to see WHICH activity happened, WHO it belongs to, and its
--    lifecycle status, but NOT the calculated commercial amounts -- those require the
--    same real, seeded COM:View selling price permission (app.has_view_selling_price)
--    COM-156 already gates its own price components behind.
-- ===========================================================================

create function app.mask_warehouse_billing_event_amounts(p_event app.warehouse_billing_events, p_masked boolean)
returns app.warehouse_billing_events
language plpgsql
immutable
as $$
declare
  v_event app.warehouse_billing_events := p_event;
begin
  if p_masked then
    v_event.contract_id := null;
    v_event.rate_component_id := null;
    v_event.base_amount := null;
    v_event.tax_code := null;
    v_event.tax_rule_version_id := null;
    v_event.tax_amount := null;
    v_event.total_amount := null;
    v_event.currency := null;
    v_event.rounding_mode := null;
    v_event.calculation_explanation := jsonb_build_object('masked', true);
  end if;
  return v_event;
end;
$$;

comment on function app.mask_warehouse_billing_event_amounts is
  'ATW-022: nulls contract_id/rate_component_id/base_amount/tax_code/tax_rule_version_id/tax_amount/total_amount/currency/rounding_mode and replaces calculation_explanation with {"masked": true} when p_masked is true -- mirrors COM-156''s own app.customer_contract_price_components_directory masking convention exactly (nulled columns, never a raw insufficient_authority for the whole row, since status/activity/ownership fields remain real and useful to an OPS:View-only reader). Internal only, no grant (called only from inside this migration''s own SECURITY DEFINER read RPCs, mirrors app.compute_warehouse_billing_breakdown''s own no-grant precedent).';

create function app.get_warehouse_billing_event(p_event_id uuid, p_actor_auth_user_id uuid)
returns app.warehouse_billing_events
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.warehouse_billing_events;
begin
  select * into v_event from app.warehouse_billing_events where id = p_event_id;
  if not found then
    raise exception 'warehouse_billing_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_event.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_event.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_event.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view billing event %', p_actor_auth_user_id, p_event_id using errcode = 'insufficient_privilege';
  end if;

  return app.mask_warehouse_billing_event_amounts(v_event, not app.has_view_selling_price(v_event.tenant_id, p_actor_auth_user_id));
end;
$$;

comment on function app.get_warehouse_billing_event is
  'ATW-022: OPS:View + record/owner-scope. Calculated commercial amounts (base_amount/tax_amount/total_amount/currency/rounding_mode/calculation_explanation/rate_component_id/contract_id) are masked (nulled) for a caller lacking COM:View selling price -- see app.mask_warehouse_billing_event_amounts.';

create function app.list_warehouse_billing_events(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_warehouse_id uuid default null,
  p_owner_account_id uuid default null,
  p_activity_type text default null,
  p_status_filter text default null,
  p_limit integer default 50
)
returns setof app.warehouse_billing_events
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
  select (app.mask_warehouse_billing_event_amounts(e, not app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id))).*
  from app.warehouse_billing_events e
  where e.tenant_id = p_tenant_id
    and (p_warehouse_id is null or e.warehouse_id = p_warehouse_id)
    and (p_owner_account_id is null or e.owner_account_id = p_owner_account_id)
    and (p_activity_type is null or e.activity_type = p_activity_type)
    and (p_status_filter is null or e.status = p_status_filter)
    and app.wms_pick_record_scope_ok(p_actor_auth_user_id, e.warehouse_id, e.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, e.owner_account_id)
  order by e.created_at desc
  limit v_limit;
end;
$$;

comment on function app.list_warehouse_billing_events is
  'ATW-022: OPS:View, bounded (p_limit clamped to [1, 200], default 50), owner/warehouse-scoped. Calculated commercial amounts are masked (nulled) per row for a caller lacking COM:View selling price -- see app.mask_warehouse_billing_event_amounts.';

create function app.get_warehouse_billing_handoff(p_handoff_id uuid, p_actor_auth_user_id uuid)
returns app.warehouse_billing_handoffs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_handoff app.warehouse_billing_handoffs;
  v_event app.warehouse_billing_events;
  v_decision app.rbac_decision;
begin
  select * into v_handoff from app.warehouse_billing_handoffs where id = p_handoff_id;
  if not found then
    raise exception 'warehouse_billing_handoff_not_found: %', p_handoff_id using errcode = 'no_data_found';
  end if;
  select * into v_event from app.warehouse_billing_events where id = v_handoff.billing_event_id;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_handoff.tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_handoff.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, v_event.warehouse_id, v_event.owner_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot view billing handoff %', p_actor_auth_user_id, p_handoff_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, v_handoff.tenant_id, v_event.owner_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped to view billing handoff %', p_actor_auth_user_id, p_handoff_id using errcode = 'insufficient_privilege';
  end if;

  return v_handoff;
end;
$$;

create function app.list_warehouse_billing_handoffs(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_billing_event_id uuid default null,
  p_limit integer default 50
)
returns setof app.warehouse_billing_handoffs
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
  select h.* from app.warehouse_billing_handoffs h
  join app.warehouse_billing_events e on e.id = h.billing_event_id
  where h.tenant_id = p_tenant_id
    and (p_billing_event_id is null or h.billing_event_id = p_billing_event_id)
    and app.wms_pick_record_scope_ok(p_actor_auth_user_id, e.warehouse_id, e.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, e.owner_account_id)
  order by h.handed_off_at desc
  limit v_limit;
end;
$$;

create function app.list_warehouse_billing_rate_components(
  p_contract_id uuid,
  p_actor_auth_user_id uuid,
  p_activity_type text default null,
  p_limit integer default 50
)
returns setof app.warehouse_billing_rate_components
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_contract app.customer_contracts;
  v_decision app.rbac_decision;
  v_limit integer;
begin
  select * into v_contract from app.customer_contracts where id = p_contract_id;
  if not found then
    raise exception 'contract_not_found: %', p_contract_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_contract.tenant_id, 'COM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_contract.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select rc.* from app.warehouse_billing_rate_components rc
  where rc.contract_id = p_contract_id
    and (p_activity_type is null or rc.activity_type = p_activity_type)
  order by rc.created_at desc
  limit v_limit;
end;
$$;

create function app.preview_warehouse_billing_calculation(
  p_tenant_id uuid,
  p_account_id uuid,
  p_warehouse_id uuid,
  p_activity_type text,
  p_quantity numeric,
  p_uom_code text,
  p_as_of timestamptz,
  p_actor_auth_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_rate app.warehouse_billing_rate_components;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.wms_pick_record_scope_ok(p_actor_auth_user_id, p_warehouse_id, p_account_id::text) then
    raise exception 'insufficient_authority: identity % cannot preview a billing calculation under warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;
  if not app.actor_can_view_owner_scoped_row(p_actor_auth_user_id, p_tenant_id, p_account_id) then
    raise exception 'insufficient_authority: identity % is not owner-scoped for account %', p_actor_auth_user_id, p_account_id using errcode = 'insufficient_privilege';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity: quantity must be positive' using errcode = 'check_violation';
  end if;
  if not app.validate_uom_code(p_uom_code) then
    raise exception 'invalid_uom_code: % is not a registered UOM code', p_uom_code using errcode = 'check_violation';
  end if;

  v_rate := app.get_effective_warehouse_billing_rate(p_tenant_id, p_account_id, p_warehouse_id, p_activity_type, coalesce(p_as_of, now()), p_actor_auth_user_id);

  -- No p_tax_code in this RPC's own signature (see migration header) -- preview never
  -- includes a tax breakdown, no row is created.
  return app.compute_warehouse_billing_breakdown(p_tenant_id, v_rate, p_quantity, p_uom_code, coalesce(p_as_of, now()), null, p_actor_auth_user_id);
end;
$$;

comment on function app.preview_warehouse_billing_calculation is
  'ATW-022: OPS:View, STABLE, creates no row -- "what would this cost" before capturing anything. Resolves the effective rate then reuses app.compute_warehouse_billing_breakdown, the identical calculation logic app.calculate_warehouse_billing_event uses.';

-- ===========================================================================
-- 8. RLS.
-- ===========================================================================

alter table app.warehouse_billing_rate_components enable row level security;
alter table app.warehouse_billing_events enable row level security;
alter table app.warehouse_billing_handoffs enable row level security;

-- Tenant-wide, not record-scoped -- mirrors app.customer_contracts' own real posture
-- (COM-156, this migration's own header correction 4): a rate component belongs to a
-- tenant-wide-visible Commercial contract, not a warehouse/owner-scoped silo.
create policy warehouse_billing_rate_components_select_scoped on app.warehouse_billing_rate_components
  for select to authenticated
  using (app.has_active_tenant_membership(tenant_id) or app.is_supreme_admin());

create policy warehouse_billing_events_select_scoped on app.warehouse_billing_events
  for select to authenticated
  using (
    app.wms_pick_record_scope_ok((select auth.uid()), warehouse_billing_events.warehouse_id, warehouse_billing_events.owner_account_id::text)
    and app.actor_can_view_owner_scoped_row((select auth.uid()), warehouse_billing_events.tenant_id, warehouse_billing_events.owner_account_id)
  );

-- A table with no owner_account_id column of its own needs a join-based RLS policy
-- (a normal, already-precedented shape) -- joins through billing_event_id to the
-- parent event's own warehouse_id/owner_account_id.
create policy warehouse_billing_handoffs_select_scoped on app.warehouse_billing_handoffs
  for select to authenticated
  using (
    exists (
      select 1 from app.warehouse_billing_events e
      where e.id = warehouse_billing_handoffs.billing_event_id
        and app.wms_pick_record_scope_ok((select auth.uid()), e.warehouse_id, e.owner_account_id::text)
        and app.actor_can_view_owner_scoped_row((select auth.uid()), e.tenant_id, e.owner_account_id)
    )
  );

-- ===========================================================================
-- 9. Grants. Per ERR-2026-004: explicit, directly-provable revoke of
--    PostgreSQL's PUBLIC-execute default, standalone, before any role-specific
--    grant.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.warehouse_billing_rate_components, app.warehouse_billing_events, app.warehouse_billing_handoffs to authenticated, service_role;
grant insert, update, delete on app.warehouse_billing_rate_components, app.warehouse_billing_events, app.warehouse_billing_handoffs to service_role;

-- Internal validation helper used inside a table CHECK constraint -- only a raw
-- service_role insert/update reaches it outside a SECURITY DEFINER RPC's own
-- owner-implicit rights (mirrors app.validate_currency_code's own service_role-only
-- posture, FIN-194).
grant execute on function app.validate_warehouse_billing_tier_schedule(jsonb) to service_role;

grant execute on function app.create_warehouse_billing_rate_component(uuid, uuid, text, text, text, numeric, numeric, text, jsonb, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_effective_warehouse_billing_rate(uuid, uuid, uuid, text, timestamptz, uuid) to authenticated, service_role;
grant execute on function app.capture_warehouse_billing_event(uuid, uuid, uuid, text, text, uuid, numeric, text, timestamptz, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.calculate_warehouse_billing_event(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.recalculate_warehouse_billing_event(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.hold_warehouse_billing_event(uuid, text, integer, uuid, text) to authenticated, service_role;
grant execute on function app.release_warehouse_billing_event_hold(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.review_warehouse_billing_event(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.approve_warehouse_billing_event(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.handoff_warehouse_billing_event(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.correct_warehouse_billing_event(uuid, integer, numeric, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.reverse_warehouse_billing_event(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_warehouse_billing_event(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_warehouse_billing_events(uuid, uuid, uuid, uuid, text, text, integer) to authenticated, service_role;
grant execute on function app.get_warehouse_billing_handoff(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_warehouse_billing_handoffs(uuid, uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.list_warehouse_billing_rate_components(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function app.preview_warehouse_billing_calculation(uuid, uuid, uuid, text, numeric, text, timestamptz, uuid) to authenticated, service_role;

-- service_role ONLY -- no authenticated grant at all (a Finance-side worker callback).
grant execute on function app.record_warehouse_billing_reconciliation_outcome(uuid, text, text, uuid, text) to service_role;
