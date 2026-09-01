-- ISS-2026-319 (docs/runtime/KNOWN_ISSUES.md) -- the same unresolved-polymorphic-id
-- shape ISS-2026-206 closed on four tables (app.inventory_movements,
-- app.inventory_reservations, app.finance_bank_transactions.matched_source_id,
-- app.finance_subledger_batches.source_id -- the last two at 20260831170000 and
-- 20260831310000 respectively), one hop further out: app.finance_ar_open_items.
-- source_document_id and app.finance_ap_open_items.source_document_id carry no FK
-- and, until this migration, no validation trigger either. Live-verified against
-- project awdlicmwzdxquopwtcfd before writing this: no trigger beyond each table's
-- own touch_row exists on either table today, and
-- app.post_finance_ar_open_item(..., 'invoice', gen_random_uuid(), ...) succeeds
-- with a random, nonexistent id -- exactly as this entry described.
--
-- Same shape, same mechanism, as 20260831310000's own
-- app.validate_finance_subledger_batch_source: a BEFORE INSERT OR UPDATE trigger
-- resolves each source_document_type against the table its real caller actually
-- populates, raising a named, errcode-tagged exception when it does not resolve.
--
-- THE LIVE CHECK CONSTRAINTS, read directly rather than assumed from the column
-- name (pg_get_constraintdef on project awdlicmwzdxquopwtcfd, matching
-- 20260729100000/20260729130000 exactly, zero drift):
--   app.finance_ar_open_items.source_document_type: 'invoice' | 'opening_balance'
--   app.finance_ap_open_items.source_document_type: 'vendor_bill' | 'opening_balance'
-- 'vendor_bill' never occurs on the AR table and 'invoice' never occurs on the AP
-- table -- each table's own CHECK constraint already forbids it, so this trigger's
-- unreachable-type else-branch (mirroring 20260831310000's own) is the only place
-- either "wrong" value could ever be evaluated.
--
-- THE TWO REAL CALL SITES PER TABLE, both read directly rather than guessed:
--   AR 'invoice'         -> app.finance_invoices, source_document_id = the
--                           invoice's own id (app.issue_finance_invoice,
--                           20260729110000:475).
--   AP 'vendor_bill'     -> app.finance_vendor_bills, source_document_id = the
--                           bill's own id (app.post_finance_vendor_bill,
--                           20260729140000:483).
--   both 'opening_balance' -> app.import_staging_rows, source_document_id = the
--                           staged import row's own id, NOT the open item and NOT
--                           a downstream document
--                           (app.commit_finance_opening_balance_import_job,
--                           20260830130000:781/810: "The staged row id IS the
--                           source document id ... the existing
--                           finance_ar_open_items_source_unique already makes
--                           that the idempotency key, and a second provenance
--                           column would be a competing source of truth.").
--
-- WHY 'opening_balance' IS ITS OWN CASE, NOT FORCED INTO THE invoice/vendor_bill
-- PATTERN. This is the one place this defect class points at a STAGING artifact
-- rather than a downstream business document -- an opening balance has no
-- originating document inside CargoGrid (20260830130000's own header: "an opening
-- balance has no originating business event ... it is a statement that money was
-- already owed on the day the tenant started"). The row it truly claims lineage
-- to is the cutover file row that asserted the number, which is exactly
-- app.import_staging_rows. This is a DIFFERENT resolution from
-- 20260831310000's own 'opening_balance' branch on
-- app.finance_subledger_batches.source_id, which is one hop further downstream
-- and points at the AR/AP open item itself (app.post_finance_opening_balance_batch
-- receives the already-created open item's id, per that migration's own header) --
-- the two tables' 'opening_balance' branches are deliberately NOT the same target,
-- because they sit at different points in the same lineage chain. Forcing this
-- table's opening_balance case through the invoice/vendor_bill resolver would have
-- rejected every real opening-balance-sourced open item ever posted.
--
-- source_document_id is NOT NULL on both tables (20260729100000/20260729130000),
-- so unlike 20260831170000's own optional matched_source_id there is no
-- legitimate absent case to preserve here -- every branch requires a real,
-- resolving id.

create function app.validate_finance_open_item_source()
returns trigger
language plpgsql
as $$
begin
  if TG_TABLE_NAME = 'finance_ar_open_items' then
    if NEW.source_document_type = 'invoice' then
      if not exists (select 1 from app.finance_invoices where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.finance_invoices row for source_document_type invoice', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    elsif NEW.source_document_type = 'opening_balance' then
      if not exists (select 1 from app.import_staging_rows where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.import_staging_rows row for source_document_type opening_balance', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    else
      -- Unreachable while finance_ar_open_items_source_type_check holds. Present
      -- so that widening that constraint without widening this function fails
      -- loudly at the first insert of the new type, instead of silently
      -- reopening the gap this migration closes -- mirrors 20260831310000's own
      -- else-branch discipline exactly.
      raise exception 'finance_open_item_unvalidated_source_type: % has no lineage rule for app.finance_ar_open_items in app.validate_finance_open_item_source -- widen the guard alongside the CHECK constraint', NEW.source_document_type
        using errcode = 'check_violation';
    end if;
  elsif TG_TABLE_NAME = 'finance_ap_open_items' then
    if NEW.source_document_type = 'vendor_bill' then
      if not exists (select 1 from app.finance_vendor_bills where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.finance_vendor_bills row for source_document_type vendor_bill', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    elsif NEW.source_document_type = 'opening_balance' then
      if not exists (select 1 from app.import_staging_rows where id = NEW.source_document_id) then
        raise exception 'finance_open_item_orphan_source: source_document_id % does not reference a real app.import_staging_rows row for source_document_type opening_balance', NEW.source_document_id
          using errcode = 'foreign_key_violation';
      end if;
    else
      raise exception 'finance_open_item_unvalidated_source_type: % has no lineage rule for app.finance_ap_open_items in app.validate_finance_open_item_source -- widen the guard alongside the CHECK constraint', NEW.source_document_type
        using errcode = 'check_violation';
    end if;
  end if;

  return NEW;
end;
$$;

comment on function app.validate_finance_open_item_source is
  'ISS-2026-319: app.finance_ar_open_items.source_document_id/app.finance_ap_open_items.source_document_id are polymorphic and carried no FK, so a direct service_role insert (or a caller passing a fabricated id) could create a receivable/payable claiming to be for a document that never existed -- live-verified on project awdlicmwzdxquopwtcfd. This one BEFORE INSERT OR UPDATE guard function serves both tables (branching on TG_TABLE_NAME): invoice/vendor_bill resolve to their own real document table; opening_balance on EITHER table resolves to app.import_staging_rows (the staged cutover row, not the open item -- see this migration''s own header for why that differs from 20260831310000''s own opening_balance branch one hop downstream on app.finance_subledger_batches).';

create trigger finance_ar_open_items_validate_source
  before insert or update on app.finance_ar_open_items
  for each row
  execute function app.validate_finance_open_item_source();

create trigger finance_ap_open_items_validate_source
  before insert or update on app.finance_ap_open_items
  for each row
  execute function app.validate_finance_open_item_source();

revoke execute on all functions in schema app from public;
