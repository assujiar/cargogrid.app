-- Track B Batch 7 -- ISS-2026-206 (found at CG-S15-HDN-007's own Tier C review, OPEN,
-- Medium, owner HDN-387): the orphan-source_id gap ISS-2026-202 closed on app.loyalty_
-- earning_events / app.finance_journals (20260812000000_harden_data_lineage_audit_
-- findings.sql -- a BEFORE INSERT OR UPDATE trigger validating a polymorphic source_type/
-- source_id pair actually resolves to a real row of the claimed type) recurs on at least 4
-- more tables one hop further up the same lineage chains. This entry's own text names all
-- 4 and already investigated 2 of them to a conclusion; this migration verifies that work
-- live against the current schema/tests and closes the 2 the entry left genuinely open.
--
-- ===========================================================================
-- Excluded (confirmed, not fixed here) -- app.finance_subledger_batches.source_id
-- ===========================================================================
-- The entry's own investigation already drafted this exact fix and found -- before
-- shipping it -- that it breaks scripts/db-tests/finance-subledger.sql's own pre-existing,
-- extensive test design, which deliberately posts app.post_finance_subledger_batch in
-- isolation from real upstream documents (~15 call sites), passing a synthetic
-- `gen_random_uuid()` source_id on purpose to test the posting primitive's own
-- idempotency/concurrency mechanics, not real lineage. Re-confirmed live by this
-- checkpoint: scripts/db-tests/finance-subledger.sql:135 `v_source_id uuid :=
-- gen_random_uuid();`, reused as the literal source_id argument at every one of that
-- file's own app.post_finance_subledger_batch calls (lines 142-256). A validation trigger
-- would fail this entire, legitimate, already-established test file. Fixing this properly
-- needs either a test-fixture rework (real resolvable ids throughout) or a considered
-- ruling on whether DB-layer resolution is even the right layer for a table whose own
-- tests treat it as an isolated posting primitive -- a design question, not a same-
-- session bounded repair, exactly as the entry itself concluded. Remains OPEN, owner
-- HDN-387/389.
--
-- ===========================================================================
-- Excluded (newly confirmed this checkpoint, same reason) -- app.finance_bank_
-- transactions.matched_source_id
-- ===========================================================================
-- The entry disclosed this one as unaudited ("matched_source_id's own real callers live
-- in the application/API layer (TypeScript)...a separate, wider audit this SQL-focused
-- checkpoint did not do"). This checkpoint did that audit and found the identical test-
-- breaking shape already ruled out for finance_subledger_batches: scripts/db-tests/
-- finance-cash-bank.sql:203 calls `app.match_finance_bank_transaction(..., 'receipt',
-- gen_random_uuid(), ...)` -- a synthetic, deliberately non-resolving matched_source_id,
-- exercising app.match_finance_bank_transaction's own state-machine mechanics (matched/
-- unmatched transitions, authority gating) in isolation from a real receipt row. A
-- validation trigger here would break this established test the same way. Excluded from
-- this migration for the same reason as finance_subledger_batches; remains OPEN, owner
-- HDN-387.
--
-- ===========================================================================
-- Fixed here -- app.inventory_movements.source_id / app.inventory_reservations.source_id
-- (Advanced TMS/WMS domain, ATW-015)
-- ===========================================================================
-- The entry itself only code-shape-inspected these two ("were only code-shape-inspected,
-- not live-forced or call-site-audited"). This checkpoint did the full call-site audit the
-- entry called for: every INSERT into either table across the whole migrations tree
-- (app.post_inventory_movement / app.reserve_inventory, the only two writers of either
-- table, and every caller of each) was read directly. Result: unlike the two excluded
-- tables above, EVERY real call site -- both production RPC callers and every scripts/
-- db-tests/*.sql fixture across 14 test files -- passes either a real, resolvable id for a
-- polymorphic source_type that names one, or a null id for a source_type that legitimately
-- carries no source document (manual/opening_balance for movements, manual for
-- reservations). No synthetic/gen_random_uuid() source_id was found anywhere for a
-- resolvable source_type -- the test-breaking shape that disqualified the two tables above
-- does not recur here. Confirmed resolvable mapping, by source_type:
--   app.inventory_movements.source_type:
--     'wms_inbound_order' -> app.wms_inbound_orders   (e.g. 20260730380000 line 565,
--                             20260730570000 line 166 -- both real v_inbound_order_id)
--     'wms_outbound_order' -> app.wms_outbound_orders  (e.g. 20260730260000 lines 877/1057,
--                             20260730380000 lines 1273/2466/2640 -- all real v_task.
--                             outbound_order_id / v_shipment.outbound_order_id)
--     'reservation'        -> app.inventory_reservations (20260730280000 line 244, real
--                             v_reservation.id, the row app.consume_inventory_reservation
--                             itself just inserted/selected)
--     'cycle_count'         -> app.cycle_count_scope_items (20260730270000 line 1050, real
--                             p_scope_item_id, the row app.approve_cycle_count_variance
--                             operates on)
--     'reversal'            -> app.inventory_movements itself (20260730190000 line 647,
--                             real p_movement_id -- the original movement being reversed)
--     'manual' / 'opening_balance' -> source_id legitimately null, never validated
--   app.inventory_reservations.source_type:
--     'wms_inbound_order' / 'wms_outbound_order' -> resolves the same way (real order ids
--                             at every call site: 20260730240000 line 1071, 20260730390000/
--                             530000 mirrors)
--     'manual'              -> source_id legitimately null, never validated
--
-- Genuinely bounded and mechanical -- same shape as ISS-2026-202's own fix, just two more
-- tables, no function body touched at all (app.post_inventory_movement/app.reserve_
-- inventory are unchanged; the guard lives entirely in a new BEFORE INSERT OR UPDATE
-- trigger on each table, the identical pattern app.validate_loyalty_earning_event_source/
-- app.validate_finance_journal_source already established).

create function app.validate_inventory_movement_source()
returns trigger
language plpgsql
as $$
begin
  if NEW.source_type = 'wms_inbound_order' then
    if NEW.source_id is null or not exists (select 1 from app.wms_inbound_orders where id = NEW.source_id) then
      raise exception 'inventory_movement_orphan_source: source_id % does not reference a real app.wms_inbound_orders row for source_type wms_inbound_order', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'wms_outbound_order' then
    if NEW.source_id is null or not exists (select 1 from app.wms_outbound_orders where id = NEW.source_id) then
      raise exception 'inventory_movement_orphan_source: source_id % does not reference a real app.wms_outbound_orders row for source_type wms_outbound_order', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'reservation' then
    if NEW.source_id is null or not exists (select 1 from app.inventory_reservations where id = NEW.source_id) then
      raise exception 'inventory_movement_orphan_source: source_id % does not reference a real app.inventory_reservations row for source_type reservation', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'cycle_count' then
    if NEW.source_id is null or not exists (select 1 from app.cycle_count_scope_items where id = NEW.source_id) then
      raise exception 'inventory_movement_orphan_source: source_id % does not reference a real app.cycle_count_scope_items row for source_type cycle_count', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'reversal' then
    if NEW.source_id is null or not exists (select 1 from app.inventory_movements where id = NEW.source_id) then
      raise exception 'inventory_movement_orphan_source: source_id % does not reference a real app.inventory_movements row for source_type reversal', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  end if;
  -- source_type in ('manual', 'opening_balance') carries no source document; source_id
  -- may legitimately remain null and is never validated.
  return NEW;
end;
$$;

comment on function app.validate_inventory_movement_source is
  'ISS-2026-206 fix (one hop further up the ISS-2026-202 lineage chain, HDN-375''s own pattern): source_id has no DB-layer FK on app.inventory_movements (source_type is polymorphic across wms_inbound_orders/wms_outbound_orders/inventory_reservations/cycle_count_scope_items/itself). This BEFORE INSERT/UPDATE guard closes the gap a direct service_role insert could otherwise exploit to create a lineage-less movement.';

create trigger inventory_movements_validate_source
  before insert or update on app.inventory_movements
  for each row
  execute function app.validate_inventory_movement_source();

create function app.validate_inventory_reservation_source()
returns trigger
language plpgsql
as $$
begin
  if NEW.source_type = 'wms_inbound_order' then
    if NEW.source_id is null or not exists (select 1 from app.wms_inbound_orders where id = NEW.source_id) then
      raise exception 'inventory_reservation_orphan_source: source_id % does not reference a real app.wms_inbound_orders row for source_type wms_inbound_order', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'wms_outbound_order' then
    if NEW.source_id is null or not exists (select 1 from app.wms_outbound_orders where id = NEW.source_id) then
      raise exception 'inventory_reservation_orphan_source: source_id % does not reference a real app.wms_outbound_orders row for source_type wms_outbound_order', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  end if;
  -- source_type = 'manual' carries no source document; source_id may legitimately
  -- remain null and is never validated.
  return NEW;
end;
$$;

comment on function app.validate_inventory_reservation_source is
  'ISS-2026-206 fix (one hop further up the ISS-2026-202 lineage chain, HDN-375''s own pattern): source_id has no DB-layer FK on app.inventory_reservations (source_type is polymorphic across wms_inbound_orders/wms_outbound_orders). This BEFORE INSERT/UPDATE guard closes the gap a direct service_role insert could otherwise exploit to create a lineage-less reservation.';

create trigger inventory_reservations_validate_source
  before insert or update on app.inventory_reservations
  for each row
  execute function app.validate_inventory_reservation_source();

revoke execute on all functions in schema app from public;
