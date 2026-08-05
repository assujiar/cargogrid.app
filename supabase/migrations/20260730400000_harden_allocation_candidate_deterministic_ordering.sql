-- CG-S10-ATW-031 (post-Prompt-248 codebase audit — closes `ISS-2026-020`).
--
-- `app.list_allocation_candidates` (`ATW-016`, Prompt 235) has a genuinely
-- non-deterministic result order. Its `order by` is:
--
--   case when v_rule = 'fefo' then coalesce(l.expiry_date, s.expiry_date) end asc nulls last,
--   case when v_rule = 'fifo' then coalesce(l.created_at, s.created_at) end asc nulls last,
--   b.updated_at asc
--
-- None of those three keys is unique. When two lots are registered inside the SAME
-- enclosing transaction — exactly what `scripts/db-tests/advanced-tms-lot-batch-serial-
-- expiry.sql`'s own fixture does, and a completely ordinary thing for a real batch
-- receiving flow to do — Postgres's `now()` is frozen for the whole transaction, so both
-- rows receive an identical `lot_identities.created_at` AND an identical
-- `inventory_balances.updated_at`. Every ordering key ties, and the relative output order
-- becomes implementation-defined: whatever physical/plan order the executor happens to
-- produce. `ISS-2026-020` recorded this as an intermittent `db:test` failure, confirmed
-- four separate times by controlled A/B testing.
--
-- It is not only a test flake. FIFO and FEFO are *inventory allocation policies* with
-- real financial and regulatory consequence (which physical lot leaves the warehouse,
-- and therefore which cost layer and which expiry date the customer receives). A policy
-- that silently returns an arbitrary order among same-timestamp lots is not implementing
-- the policy it claims to implement.
--
-- ===========================================================================
-- Repair
-- ===========================================================================
--
-- 1. A genuine monotonic registration sequence on both identity tables:
--    `registration_seq bigint generated always as identity`. This is exactly the shape
--    `ATW-024` already established for the analogous non-determinism it hit on
--    `app.claim_settlement_readiness_handoffs.handoff_seq`
--    (`20260730340000_create_advanced_tms_claim_incident_operations.sql` line 801) — the
--    same problem, the same ratified remedy, so this introduces no new convention.
--    Unlike `created_at`, an identity column advances per INSERT, never per transaction,
--    so two lots registered in one transaction are strictly ordered by the order they
--    were actually registered in.
--
-- 2. `app.list_allocation_candidates` gains two further ordering keys, in this order:
--      ... coalesce(l.registration_seq, s.registration_seq) asc nulls last,
--          b.updated_at asc,
--          b.id asc
--    `registration_seq` resolves same-timestamp ties in TRUE registration order (which
--    is what both FIFO and FEFO mean when their primary key ties). `b.id` is appended
--    last purely as a totality guarantee: `inventory_balances.id` is unique, so the sort
--    is now a total order and the function can never again return two rows in an
--    unspecified sequence, for any input, including plain non-lot-controlled items where
--    every identity-derived key is NULL.
--
-- Ordering semantics for existing callers are unchanged wherever the existing keys
-- already discriminated — the new keys only ever break a tie that was previously
-- resolved arbitrarily. `ATW-017`'s `app.generate_wms_pick_task` auto-select path
-- consumes this function's first row, so it inherits the determinism directly.
--
-- ===========================================================================
-- Safety
-- ===========================================================================
--
-- Additive only: two new columns (each `generated always as identity`, so no existing
-- INSERT statement anywhere needs to change and none can write it), and one
-- `CREATE OR REPLACE FUNCTION` on an identical signature. No column is dropped or
-- retyped, no constraint or policy is touched, and no already-applied migration file is
-- edited. Backfill is automatic: `ADD COLUMN ... GENERATED ALWAYS AS IDENTITY` assigns
-- every pre-existing row a value as part of the same statement.
--
-- Row-type note: `app.lot_identities`/`app.serial_identities` are used as composite
-- return types (`app.register_lot_identity`, `app.register_serial_identity`), so those
-- functions now return one extra column. Verified safe: the TypeScript contracts that
-- parse them (`server/contracts/lot-batch-serial/lot-batch-serial.ts`,
-- `customer-inventory-access.ts`) are plain `z.object()` schemas, not `.strict()`, so an
-- unmodelled column is stripped rather than rejected.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grant.

alter table app.lot_identities
  add column registration_seq bigint generated always as identity;

alter table app.serial_identities
  add column registration_seq bigint generated always as identity;

comment on column app.lot_identities.registration_seq is
  'ATW-031 (ISS-2026-020): strictly monotonic per-INSERT registration sequence. Exists because created_at is frozen per transaction, so two lots registered in one transaction are indistinguishable by timestamp -- which made app.list_allocation_candidates'' FIFO/FEFO ordering implementation-defined. Mirrors app.claim_settlement_readiness_handoffs.handoff_seq (ATW-024).';

comment on column app.serial_identities.registration_seq is
  'ATW-031 (ISS-2026-020): strictly monotonic per-INSERT registration sequence -- see app.lot_identities.registration_seq.';

create index if not exists lot_identities_registration_seq_idx
  on app.lot_identities (tenant_id, item_master_id, registration_seq);

create index if not exists serial_identities_registration_seq_idx
  on app.serial_identities (tenant_id, item_master_id, registration_seq);

create or replace function app.list_allocation_candidates(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_item_master_id uuid,
  p_owner_account_id uuid,
  p_actor_auth_user_id uuid,
  p_allocation_rule text default null,
  p_limit integer default 50
)
returns table (
  balance_id uuid,
  location_id uuid,
  lot_number text,
  serial_number text,
  manufacture_date date,
  expiry_date date,
  available numeric,
  lot_status text,
  serial_status text,
  near_expiry boolean
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_warehouse app.warehouses;
  v_rule text;
  v_near_expiry_days integer;
  v_limit integer;
begin
  select * into v_warehouse from app.warehouses where id = p_warehouse_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'warehouse_not_found: % is not a warehouse of tenant %', p_warehouse_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'OPS', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if not app.can_access_record(p_actor_auth_user_id, p_tenant_id, null, app.lead_record_scope_org_unit_ids(v_warehouse.company_org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot view warehouse %', p_actor_auth_user_id, p_warehouse_id using errcode = 'insufficient_privilege';
  end if;

  select allocation_rule, near_expiry_warning_days into v_rule, v_near_expiry_days
    from app.item_control_policy_versions where item_master_id = p_item_master_id and status = 'published' and effective_from <= now();
  v_rule := coalesce(p_allocation_rule, v_rule, 'fifo');
  if v_rule not in ('fifo', 'fefo') then
    raise exception 'invalid_allocation_rule: % is not a recognized allocation rule', v_rule using errcode = 'check_violation';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    b.id,
    b.location_id,
    b.lot_number,
    b.serial_number,
    coalesce(l.manufacture_date, s.manufacture_date),
    coalesce(l.expiry_date, s.expiry_date),
    b.available,
    l.status,
    s.status,
    (v_near_expiry_days is not null and coalesce(l.expiry_date, s.expiry_date) is not null
      and coalesce(l.expiry_date, s.expiry_date) <= (current_date + make_interval(days => v_near_expiry_days)))
  from app.inventory_balances b
  left join app.lot_identities l on l.tenant_id = b.tenant_id and l.owner_account_id = b.owner_account_id and l.item_master_id = b.item_master_id and l.lot_number = b.lot_number and b.lot_number is not null
  left join app.serial_identities s on s.tenant_id = b.tenant_id and s.owner_account_id = b.owner_account_id and s.item_master_id = b.item_master_id and s.serial_number = b.serial_number and b.serial_number is not null
  where b.tenant_id = p_tenant_id
    and b.warehouse_id = p_warehouse_id
    and b.item_master_id = p_item_master_id
    and (p_owner_account_id is null or b.owner_account_id = p_owner_account_id)
    and b.status = 'on_hand'
    and b.available > 0
    and (l.id is null or l.status = 'active')
    and (s.id is null or s.status = 'active')
    and (l.id is null or l.expiry_date is null or l.expiry_date >= current_date)
    and (s.id is null or s.expiry_date is null or s.expiry_date >= current_date)
  order by
    case when v_rule = 'fefo' then coalesce(l.expiry_date, s.expiry_date) end asc nulls last,
    case when v_rule = 'fifo' then coalesce(l.created_at, s.created_at) end asc nulls last,
    -- ATW-031 (ISS-2026-020): the three keys above are all non-unique and all tie when
    -- two lots are registered in one transaction. registration_seq resolves that tie in
    -- true registration order; b.id makes the sort a total order so no input can ever
    -- again produce an implementation-defined sequence.
    coalesce(l.registration_seq, s.registration_seq) asc nulls last,
    b.updated_at asc,
    b.id asc
  limit v_limit;
end;
$$;

comment on function app.list_allocation_candidates is
  'ATW-016, hardened at ATW-031 (ISS-2026-020): FIFO/FEFO allocation candidates for one item in one warehouse, excluding held/expired lot and serial identities. Ordering is a TOTAL order -- expiry (fefo) or lot creation (fifo), then lot/serial registration_seq to resolve same-transaction ties in true registration order, then balance updated_at, then balance id. Before ATW-031 every ordering key was non-unique, so two lots registered in one transaction were returned in implementation-defined order.';

revoke execute on all functions in schema app from public;

-- Re-granted exactly as ATW-016's own migration did. CREATE OR REPLACE preserves a prior
-- grant automatically; restated here for this migration's own self-contained auditability.
grant execute on function app.list_allocation_candidates(uuid, uuid, uuid, uuid, uuid, text, integer) to authenticated, service_role;
