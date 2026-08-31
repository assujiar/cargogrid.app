-- ISS-2026-259 (docs/runtime/KNOWN_ISSUES.md) -- app.audit_logs is structurally blind to
-- raw-SQL or infra-level data corruption.
--
-- 20260828200000 built the detection mechanism and attached it to exactly 2 tables (app.leads,
-- the table HDN-384's own live reproduction used, and app.audit_logs itself), disclosing that
-- "the 9 tables ISS-2026-265 separately named remain uncovered -- extending the mechanism to
-- them is mechanical follow-up". This is that follow-up, and it is genuinely mechanical: the
-- trigger function, the log table, the correlation column and the read RPC are all unchanged.
-- Only the set of tables watched grows, from 2 to 11.
--
-- WHY THESE 9 AND NOT ALL 300-ODD app.* TABLES. Each of these carries a security or integrity
-- row-level trigger that ISS-2026-265 live-proved is silently defeated by the TRUNCATE step in
-- this repository's own sanctioned in-place restore procedure -- TRUNCATE never fires a FOR
-- EACH ROW trigger at all, which is documented Postgres behaviour and independent of
-- pg_restore's --disable-triggers flag:
--
--   app.files                                legal-hold delete protection (RPD-025)
--   app.finance_journals                     posted-journal immutability (RPD-022 / FIN-204)
--   app.finance_journal_lines                        "
--   app.loyalty_earning_events               append-only ledger guarantee (CPL-325)
--   app.loyalty_point_ledger_entries                 "
--   app.loyalty_benefit_entitlement_events           "
--   app.loyalty_reward_stock_reservations            "
--   app.loyalty_redemption_events                    "
--   app.transaction_lineage_edges            append-only lineage guarantee (HDN-375 / OPS-184)
--
-- These are the guarantees this product treats as load-bearing: legal hold, financial
-- immutability, append-only ledgers, lineage. A statement-level trigger fires on TRUNCATE
-- where a row-level one does not, so covering exactly the tables whose row-level protection
-- TRUNCATE defeats is the whole point -- watching every table would bury these in noise from
-- ordinary bulk operations against tables nobody promised anything about.
--
-- WHAT THIS DOES NOT CLAIM. It does not stop anything. A tripwire records; the row-level
-- guards still do the refusing, and TRUNCATE still defeats them. What changes is that an
-- interrupted restore, a botched migration or a support engineer's direct psql intervention
-- against one of these 9 now leaves a durable trace in public.raw_mutation_tripwire_log --
-- deliberately in `public` so it survives an `app` schema restore -- correlated against
-- app.audit_logs by txid_current(), so app.list_untracked_table_mutations() reports exactly
-- which mutations had no matching audit entry in their own transaction.
--
-- The transaction-granular correlation limitation 20260828200000 disclosed is unchanged and
-- inherited: a multi-statement raw transaction that audits one mutation but not a second in
-- the same transaction would not flag the second. The single-autocommit-statement threat model
-- this targets is unaffected.
--
-- Postgres rejects a transition table on a trigger covering more than one event, so DELETE and
-- UPDATE need separate single-event triggers and TRUNCATE takes no transition table at all --
-- 3 triggers per table, 27 in total, every one calling the unchanged
-- app._raw_mutation_tripwire.

-- ---------------------------------------------------------------------------------------
-- app.files -- legal-hold delete protection (RPD-025).
-- ---------------------------------------------------------------------------------------
create trigger files_raw_mutation_tripwire_delete
  after delete on app.files
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger files_raw_mutation_tripwire_update
  after update on app.files
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger files_raw_mutation_tripwire_truncate
  after truncate on app.files
  for each statement
  execute function app._raw_mutation_tripwire();

-- ---------------------------------------------------------------------------------------
-- app.finance_journals / app.finance_journal_lines -- posted-journal immutability.
-- ---------------------------------------------------------------------------------------
create trigger finance_journals_raw_mutation_tripwire_delete
  after delete on app.finance_journals
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger finance_journals_raw_mutation_tripwire_update
  after update on app.finance_journals
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger finance_journals_raw_mutation_tripwire_truncate
  after truncate on app.finance_journals
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger finance_journal_lines_raw_mutation_tripwire_delete
  after delete on app.finance_journal_lines
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger finance_journal_lines_raw_mutation_tripwire_update
  after update on app.finance_journal_lines
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger finance_journal_lines_raw_mutation_tripwire_truncate
  after truncate on app.finance_journal_lines
  for each statement
  execute function app._raw_mutation_tripwire();

-- ---------------------------------------------------------------------------------------
-- The 5 append-only loyalty ledgers (CPL-325).
-- ---------------------------------------------------------------------------------------
create trigger loyalty_earning_events_raw_mutation_tripwire_delete
  after delete on app.loyalty_earning_events
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_earning_events_raw_mutation_tripwire_update
  after update on app.loyalty_earning_events
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_earning_events_raw_mutation_tripwire_truncate
  after truncate on app.loyalty_earning_events
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_point_ledger_entries_raw_mutation_tripwire_delete
  after delete on app.loyalty_point_ledger_entries
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_point_ledger_entries_raw_mutation_tripwire_update
  after update on app.loyalty_point_ledger_entries
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_point_ledger_entries_raw_mutation_tripwire_truncate
  after truncate on app.loyalty_point_ledger_entries
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_benefit_entitlement_events_raw_mutation_tripwire_delete
  after delete on app.loyalty_benefit_entitlement_events
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_benefit_entitlement_events_raw_mutation_tripwire_update
  after update on app.loyalty_benefit_entitlement_events
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_benefit_entitlement_events_raw_mutation_tripwire_truncate
  after truncate on app.loyalty_benefit_entitlement_events
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_reward_stock_reservations_raw_mutation_tripwire_delete
  after delete on app.loyalty_reward_stock_reservations
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_reward_stock_reservations_raw_mutation_tripwire_update
  after update on app.loyalty_reward_stock_reservations
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_reward_stock_reservations_raw_mutation_tripwire_truncate
  after truncate on app.loyalty_reward_stock_reservations
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_redemption_events_raw_mutation_tripwire_delete
  after delete on app.loyalty_redemption_events
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_redemption_events_raw_mutation_tripwire_update
  after update on app.loyalty_redemption_events
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger loyalty_redemption_events_raw_mutation_tripwire_truncate
  after truncate on app.loyalty_redemption_events
  for each statement
  execute function app._raw_mutation_tripwire();

-- ---------------------------------------------------------------------------------------
-- app.transaction_lineage_edges -- append-only lineage guarantee.
-- ---------------------------------------------------------------------------------------
create trigger transaction_lineage_edges_raw_mutation_tripwire_delete
  after delete on app.transaction_lineage_edges
  referencing old table as old_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger transaction_lineage_edges_raw_mutation_tripwire_update
  after update on app.transaction_lineage_edges
  referencing new table as new_rows
  for each statement
  execute function app._raw_mutation_tripwire();

create trigger transaction_lineage_edges_raw_mutation_tripwire_truncate
  after truncate on app.transaction_lineage_edges
  for each statement
  execute function app._raw_mutation_tripwire();
