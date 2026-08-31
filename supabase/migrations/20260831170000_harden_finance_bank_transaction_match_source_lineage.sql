-- `ISS-2026-206`, third of the four tables that entry named: `app.finance_bank_transactions`
-- `.matched_source_id`. Two (`app.inventory_movements`, `app.inventory_reservations`) were closed
-- at `20260828151000`; this closes the third; the fourth stays open for reasons re-derived and
-- recorded on the entry this checkpoint.
--
-- THE GAP
--
--   `app.match_finance_bank_transaction` (`20260730480000:999`) whitelists `matched_source_type`
--   against ('receipt', 'settlement', 'manual') and then **never resolves `matched_source_id`**.
--   Nothing anywhere does. So a bank statement line can carry a hard claim — "this line is the
--   money for receipt X" — where X is a uuid matching no receipt that has ever existed.
--
--   That is a worse class of wrong than a missing link. A reconciliation that shows an unmatched
--   line is visibly incomplete and someone chases it. A line matched to a fabricated receipt looks
--   *settled*, and nobody chases it at all.
--
-- WHY THIS ONE WAS DEFERRED, AND WHY IT NO LONGER NEEDS TO BE
--
--   `ISS-2026-206` set this table aside because "its own real callers live in the application/API
--   layer (TypeScript), not SQL migrations, so verifying them is a separate, wider audit this
--   SQL-focused checkpoint did not do." That audit is done now, and it is small:
--   `server/mutations/cash-bank.ts` is the only TypeScript caller and it forwards its argument
--   unchanged; `app/(tenant)/[tenantSlug]/finance/cash-bank/cash-bank-forms.tsx:128` is the only
--   UI, and it presents the field as "Source ID (optional)". `MatchFinanceBankTransactionInput
--   Schema` types it `.uuid().nullable()`. No caller fabricates an id.
--
-- WHAT IS DELIBERATELY *NOT* CHANGED: A NULL ID STAYS LEGAL
--
--   The guard validates an id that is **given**, and says nothing about one that is absent. That
--   is not an oversight and it is not a weakening: `matched_source_id` is nullable by design, the
--   UI offers it as optional, and the table's own CHECK requires only `matched_source_type` on a
--   matched row.
--
--   The distinction that matters: a null id makes **no claim** about which document this line is,
--   which is merely incomplete. A non-resolving id makes a **false** one. `ISS-2026-202`'s whole
--   subject is the false claim -- an "orphan source_id" -- and that is exactly what this closes.
--   Requiring a non-null id for receipt/settlement would be a separate behaviour change that
--   breaks a supported UI flow, and it is not smuggled in here.
--
--   `matched_source_type = 'manual'` carries no source document at all, mirroring the
--   `manual`/`opening_balance` exemption `app.validate_inventory_movement_source` established.

create function app.validate_finance_bank_transaction_match_source()
returns trigger
language plpgsql
as $$
begin
  -- Only a claim that was actually made is checked. See the header: absent is incomplete,
  -- fabricated is false, and only the false one is this guard's subject.
  if NEW.matched_source_id is null then
    return NEW;
  end if;

  if NEW.matched_source_type = 'receipt' then
    if not exists (select 1 from app.finance_receipts where id = NEW.matched_source_id) then
      raise exception 'finance_bank_transaction_orphan_match_source: matched_source_id % does not reference a real app.finance_receipts row for matched_source_type receipt', NEW.matched_source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.matched_source_type = 'settlement' then
    if not exists (select 1 from app.finance_settlements where id = NEW.matched_source_id) then
      raise exception 'finance_bank_transaction_orphan_match_source: matched_source_id % does not reference a real app.finance_settlements row for matched_source_type settlement', NEW.matched_source_id
        using errcode = 'foreign_key_violation';
    end if;
  end if;
  -- matched_source_type = 'manual' carries no source document; an id given alongside it is not
  -- resolvable against any table by construction and is left alone rather than guessed at.
  return NEW;
end;
$$;

comment on function app.validate_finance_bank_transaction_match_source is
  'ISS-2026-206 (third of the four tables that entry named; ISS-2026-202/HDN-375''s own proven pattern). matched_source_id has no DB-layer FK -- matched_source_type is polymorphic across finance_receipts/finance_settlements/manual -- so app.match_finance_bank_transaction validated the TYPE and never the ID. This BEFORE INSERT OR UPDATE guard closes the gap a direct service_role insert could otherwise use to mark a statement line settled against a receipt that never existed, which reads as reconciled and so is never chased. A NULL id stays legal on purpose: absent is incomplete, fabricated is false, and only the false claim is this guard''s subject.';

create trigger finance_bank_transactions_validate_match_source
  before insert or update on app.finance_bank_transactions
  for each row
  execute function app.validate_finance_bank_transaction_match_source();
