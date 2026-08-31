-- ISS-2026-206 (docs/runtime/KNOWN_ISSUES.md) -- the fourth and last of the tables that entry
-- named: app.finance_subledger_batches.source_id.
--
-- Two (app.inventory_movements, app.inventory_reservations) closed at 20260828151000; the
-- third (app.finance_bank_transactions.matched_source_id) at 20260831170000. This one stayed
-- open longest for a stated reason, and the reason was real: a validation trigger drafted at
-- CG-S15-HDN-007 broke scripts/db-tests/finance-subledger.sql, which deliberately drives
-- app.post_finance_subledger_batch with gen_random_uuid() source ids across many call sites to
-- exercise the posting primitive's own mechanics in isolation from real document creation. The
-- entry recorded the fix shape rather than forcing it: "updating any test fixture that
-- currently relies on a synthetic non-resolving id to use a real one, rather than working
-- around the new guard." That is what this change does.
--
-- WHY THE GAP MATTERS, restated concretely. app.finance_subledger_batches.source_id is the
-- claim "this GL batch is the accounting for document X". ISS-2026-202 already guards
-- app.finance_journals.source_id against app.finance_subledger_batches.id -- so a journal can
-- no longer point at a fabricated batch. Until now a batch could still point at a fabricated
-- invoice, which left the journal lineage-less at its actual root and quietly weakened the
-- guard one hop above it. A missing link is visibly incomplete and someone chases it; a link
-- to a document that never existed looks settled, and nobody does.
--
-- FIVE SOURCE TYPES, NOT FOUR. The entry, and the table's own original CHECK constraint, name
-- four. A live read of the constraint returns five: 'opening_balance' was added later, by
-- app.post_finance_opening_balance_batch (the ISS-2026-273 finance opening-balance import),
-- and it resolves differently from the rest -- its source_id is an AR **or** AP open item,
-- not one table. Every one of the five was derived by reading what the real caller actually
-- passes, out of the live pg_proc definition, rather than from the column name:
--
--   invoice             -> app.finance_invoices                  (app.issue_finance_invoice)
--   receipt_allocation  -> app.finance_receipt_allocation_batches (app.allocate_finance_receipt)
--   vendor_bill         -> app.finance_vendor_bills              (app.post_finance_vendor_bill)
--   settlement          -> app.finance_settlements               (app.post_finance_settlement)
--   opening_balance     -> app.finance_ar_open_items OR app.finance_ap_open_items
--                                                     (app.post_finance_opening_balance_batch)
--
-- receipt_allocation is the one a reader would most likely get wrong: the caller passes the
-- allocation BATCH id, not a row from app.finance_receipt_allocations. A guard pointed at the
-- plural-sounding table would have rejected every legitimate receipt allocation in production.
--
-- WHAT IS DELIBERATELY NOT CHANGED. source_id is NOT NULL on this table, so unlike
-- ISS-2026-202's own 'manual' journals and 20260831170000's optional matched_source_id there
-- is no legitimate absent case to preserve here. An unrecognised source_type cannot occur --
-- the CHECK constraint rejects it first -- so the guard has no else branch that could silently
-- pass an unknown type; if the CHECK is ever widened again without widening this function, the
-- new type falls through to the explicit failure below rather than being waved past.

create function app.validate_finance_subledger_batch_source()
returns trigger
language plpgsql
as $$
begin
  if NEW.source_type = 'invoice' then
    if not exists (select 1 from app.finance_invoices where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_invoices row for source_type invoice', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'receipt_allocation' then
    -- The allocation BATCH, not app.finance_receipt_allocations -- see the header note.
    if not exists (select 1 from app.finance_receipt_allocation_batches where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_receipt_allocation_batches row for source_type receipt_allocation', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'vendor_bill' then
    if not exists (select 1 from app.finance_vendor_bills where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_vendor_bills row for source_type vendor_bill', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'settlement' then
    if not exists (select 1 from app.finance_settlements where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_settlements row for source_type settlement', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'opening_balance' then
    if not exists (select 1 from app.finance_ar_open_items where id = NEW.source_id)
       and not exists (select 1 from app.finance_ap_open_items where id = NEW.source_id) then
      raise exception 'finance_subledger_orphan_source: source_id % does not reference a real app.finance_ar_open_items or app.finance_ap_open_items row for source_type opening_balance', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  else
    -- Unreachable while the table's own CHECK constraint holds. Present so that widening that
    -- constraint without widening this function fails loudly at the first insert of the new
    -- type, instead of silently reopening the gap this migration closes.
    raise exception 'finance_subledger_unvalidated_source_type: % has no lineage rule in app.validate_finance_subledger_batch_source -- widen the guard alongside the CHECK constraint', NEW.source_type
      using errcode = 'check_violation';
  end if;

  return NEW;
end;
$$;

comment on function app.validate_finance_subledger_batch_source is
  'ISS-2026-206: app.finance_subledger_batches.source_id is polymorphic across five source types and carries no FK, so a direct service_role insert could create a GL batch claiming to be the accounting for a document that never existed -- live-forced at CG-S15-HDN-007. This BEFORE INSERT OR UPDATE guard resolves each source_type against the table its real caller actually reads, closing the last of the four tables ISS-2026-206 named and restoring the lineage root that ISS-2026-202''s own guard on app.finance_journals depends on.';

create trigger finance_subledger_batches_validate_source
  before insert or update on app.finance_subledger_batches
  for each row
  execute function app.validate_finance_subledger_batch_source();

revoke execute on all functions in schema app from public;
