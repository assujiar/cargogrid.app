-- HDN-375 (Step 15, Prompt 375, Data Lineage Audit, `CG-S15-HDN-007`) -- four independent
-- parallel investigation lenses (canonical lineage chain; downstream projection versioning;
-- hash-chain triggers and historical config preservation; orphan records and no-silent-
-- reentry), each required to live-force its own findings on disposable databases rather
-- than accept a code read as proof. Canonical lineage (lead through loyalty), projection
-- versioning, historical config preservation, lineage permission-awareness, and legacy/
-- import source-tracking all held clean. Two real, live-forced gaps are fixed here.
--
-- ===========================================================================
-- Finding 1 -- app.transaction_lineage_edges (OPS-184's own lineage-evidence ledger) is
-- freely UPDATE/DELETE-able by service_role despite its own table comment claiming
-- "append-only, never-updated, never-deleted" (High)
-- ===========================================================================
--
-- **Live-forced**: a raw `UPDATE app.transaction_lineage_edges set source_version_hash =
-- ... where id = ...` succeeded with zero rows affected by any guard -- `pg_trigger` on
-- this table returned 0 rows (no BEFORE UPDATE/DELETE trigger exists at all), and
-- `information_schema.role_table_grants` confirms `service_role` (what every backend call
-- and every `SECURITY DEFINER` function runs as) holds live `UPDATE`/`DELETE`. The
-- rewrite also bypasses `app.capture_audit_event` entirely (only called from the insert
-- path and the explicit, reasoned `app.record_transaction_lineage_override` RPC), leaving
-- no audit trail either. This directly contradicts the table's own documented contract
-- ("OPS-184: one append-only, never-updated, never-deleted row...") and this checkpoint's
-- own charter (Prompt 375: "Make CargoGrid explainable, auditable and recoverable").
--
-- This exact class of gap was already found and disclosed once before, for a DIFFERENT
-- set of tables: `20260801280000_harden_customer_portal_loyalty_ledger_supreme_admin_
-- override.sql` (CPL-325, ISS-2026-130) added a shared BEFORE UPDATE/DELETE guard to 5
-- Phase 8 loyalty-ledger tables, and its own migration header explicitly disclosed
-- "does NOT retroactively cover app.inventory_movements or any other pre-existing
-- append_only_ledger-family table (disclosed, out of this checkpoint's own authority)".
-- `app.transaction_lineage_edges` is exactly one of those other tables -- this checkpoint
-- is the first with the authority and the charter (data lineage integrity) to close it.
--
-- **Fix**: mirror CPL-325's own proven pattern exactly -- a dedicated BEFORE UPDATE/
-- DELETE trigger function scoped to this one table (not reusing the loyalty-named
-- function, to keep each domain's own guard independently scoped and readable), blocking
-- any mutation unless `app.is_supreme_admin(auth.uid())`, with a best-effort
-- `app.capture_audit_event` disclosure on the exception path. Per RPD-022/034, this is a
-- detective, best-effort-evidenced control, never a tamper-proof claim -- a Supreme Admin
-- who also controls the database directly is an accepted residual risk, same as every
-- other append-only ledger in this codebase.
--
-- ===========================================================================
-- Finding 2 -- app.loyalty_earning_events / app.finance_journals accept a source_id that
-- resolves to no real row, enforced only by RPC discipline, not the schema (Medium)
-- ===========================================================================
--
-- **Live-forced**: as `service_role` (bypassing the validating RPC entirely, exactly the
-- role every real backend call runs as), a direct `INSERT` succeeded on both
-- `app.loyalty_earning_events` (a `source_id` matching no row in `app.finance_ar_open_
-- items`) and `app.finance_journals` (`source_type='subledger'`, a `source_id` matching
-- no row in `app.finance_subledger_batches`). Neither table has a DB-layer FK or trigger
-- requiring `source_id` to resolve -- only the RPC layer (`app.evaluate_customer_loyalty_
-- earning_for_paid_invoice`, `app.create_and_post_finance_system_journal`) validates it.
-- Mitigated in practice (no application code ever inserts directly), but not a structural
-- guarantee -- a future direct-insert path or a compromised service-role key could
-- silently create a lineage-less financial/loyalty record, exactly the "no orphaned
-- critical records" business rule this lane's own charter states (Prompt 375 §24).
--
-- **Fix**: a lightweight BEFORE INSERT OR UPDATE trigger on each table validating
-- `source_id` resolves to a real row of the type its own `source_type` claims --
-- `app.loyalty_earning_events`: `finance_invoice_paid` -> `app.finance_ar_open_items`,
-- `reversal` -> `app.loyalty_earning_events` itself (the original event being reversed,
-- confirmed by reading `app.reverse_loyalty_earning_event`'s own insert -- it passes
-- `v_original.id` as `source_id`, the identical value already used for `corrects_event_
-- id`); `app.finance_journals`: `subledger` -> `app.finance_subledger_batches`,
-- `correction` -> `app.finance_journal_corrections`, `manual` -> no source document
-- required, `source_id` may legitimately be null (a purely manual entry). Every existing
-- legitimate RPC-driven row already satisfies these predicates (confirmed by the full
-- 229-file db-test suite passing unchanged after this migration) -- this closes the gap
-- without narrowing any real, sanctioned insert path.
--
-- ===========================================================================
-- Finding 3 -- the 5 "hash-chain" lineage triggers are standalone content fingerprints,
-- not a genuine tamper-evident chain, and no reconciliation ever recomputes or compares
-- them (High, registered, not fixed here)
-- ===========================================================================
--
-- Each of `app.trg_capture_lineage_job_to_shipment`/`_shipment_to_epod`/`_shipment_to_
-- cost`/`_job_to_profitability`/`_job_to_billing_readiness` (`20260728170000_create_
-- operations_transaction_lineage.sql`, OPS-184) computes `source_version_hash :=
-- encode(digest(<that node's own current-row fields>, 'sha256'), 'hex')` -- a fingerprint
-- of ONE row, with no reference anywhere to a prior edge's own hash. A genuine hash chain
-- requires `H_n = f(H_{n-1}, content_n)`; nothing here does that. **Live-forced**: a raw
-- `UPDATE` tampering with a source row's own content produces a real, detectable hash
-- mismatch on manual recomputation -- but `app.detect_transaction_lineage_anomalies` (the
-- only reconciliation function this capability ships) has exactly 4 anomaly types
-- (`orphan_shipment_order`, `orphan_billing_readiness`, `duplicate_target`, `cross_
-- tenant_mismatch`) and NO hash-mismatch/tamper-detection type at all -- `source_version_
-- hash` is write-only and display-only everywhere in this repository, never recomputed
-- and compared by anything.
--
-- **Not fixed here.** Implementing a genuine tamper-evident chain (defining a canonical
-- per-relation-type ordering, a real `prev_hash` column, backfilling all existing rows'
-- own chain position, and extending `detect_transaction_lineage_anomalies` with a real
-- hash-mismatch check) is a design decision -- not a bounded repair -- outside this
-- checkpoint's own charter. Registered `ISS-2026-200`/`HDN-BLK-017` (High), owner
-- `HDN-386`. Finding 1's own fix (above) closes the narrower, bounded-repair-sized half
-- of this same area (the evidence ledger's own mutability), which is a real, independent
-- improvement regardless of when/whether genuine chaining is later built.
--
-- Full disposition: `docs/build-log/full-system-hardening/HDN-375.md` §6.

-- ===========================================================================
-- Finding 1 fix
-- ===========================================================================

create function app.protect_transaction_lineage_edges_append_only()
returns trigger
language plpgsql
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not app.is_supreme_admin(v_actor) then
    raise exception 'transaction_lineage_edge_append_only_immutable: normal roles cannot % row % of append-only app.transaction_lineage_edges -- record a new edge or use app.record_transaction_lineage_override instead', lower(TG_OP), OLD.id
      using errcode = 'insufficient_privilege';
  end if;

  perform app.capture_audit_event(
    OLD.tenant_id, v_actor, 'supreme_admin_absolute_crud', lower(TG_OP) || '_append_only_transaction_lineage_edge',
    'app.transaction_lineage_edges', OLD.id, 'success',
    'RPD-022 absolute-CRUD exception invoked (best-effort evidence, not a preventive control) -- transaction_lineage_edges is otherwise a fully append-only ledger',
    to_jsonb(OLD), case when TG_OP = 'DELETE' then null else to_jsonb(NEW) end
  );

  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;

comment on function app.protect_transaction_lineage_edges_append_only is
  'HDN-375 (Data Lineage Audit): BEFORE UPDATE/DELETE guard for app.transaction_lineage_edges, mirroring app.protect_loyalty_ledger_append_only''s own proven CPL-325 shape exactly. Blocks any mutation unless app.is_supreme_admin(auth.uid()) -- a detective, best-effort-evidenced RPD-022 exception, never a tamper-proof claim.';

create trigger transaction_lineage_edges_protect_append_only
  before update or delete on app.transaction_lineage_edges
  for each row
  execute function app.protect_transaction_lineage_edges_append_only();

-- ===========================================================================
-- Finding 2 fix
-- ===========================================================================

create function app.validate_loyalty_earning_event_source()
returns trigger
language plpgsql
as $$
begin
  if NEW.source_type = 'finance_invoice_paid' then
    if not exists (select 1 from app.finance_ar_open_items where id = NEW.source_id) then
      raise exception 'loyalty_earning_event_orphan_source: source_id % does not reference a real app.finance_ar_open_items row for source_type finance_invoice_paid', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'reversal' then
    if not exists (select 1 from app.loyalty_earning_events where id = NEW.source_id) then
      raise exception 'loyalty_earning_event_orphan_source: source_id % does not reference a real app.loyalty_earning_events row for source_type reversal', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  end if;
  return NEW;
end;
$$;

comment on function app.validate_loyalty_earning_event_source is
  'HDN-375 (Data Lineage Audit) finding 2: source_id has no DB-layer FK (source_type is polymorphic across finance_ar_open_items and loyalty_earning_events itself) -- this BEFORE INSERT/UPDATE guard closes the gap a direct service_role insert could otherwise exploit to create a lineage-less earning event, live-forced during this checkpoint''s own investigation.';

create trigger loyalty_earning_events_validate_source
  before insert or update on app.loyalty_earning_events
  for each row
  execute function app.validate_loyalty_earning_event_source();

create function app.validate_finance_journal_source()
returns trigger
language plpgsql
as $$
begin
  if NEW.source_type = 'subledger' then
    if NEW.source_id is null or not exists (select 1 from app.finance_subledger_batches where id = NEW.source_id) then
      raise exception 'finance_journal_orphan_source: source_id % does not reference a real app.finance_subledger_batches row for source_type subledger', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  elsif NEW.source_type = 'correction' then
    if NEW.source_id is null or not exists (select 1 from app.finance_journal_corrections where id = NEW.source_id) then
      raise exception 'finance_journal_orphan_source: source_id % does not reference a real app.finance_journal_corrections row for source_type correction', NEW.source_id
        using errcode = 'foreign_key_violation';
    end if;
  end if;
  -- source_type = 'manual' requires no source document; source_id may legitimately be null.
  return NEW;
end;
$$;

comment on function app.validate_finance_journal_source is
  'HDN-375 (Data Lineage Audit) finding 2: source_id has no DB-layer FK (source_type is polymorphic across finance_subledger_batches/finance_journal_corrections, and legitimately null for manual) -- this BEFORE INSERT/UPDATE guard closes the gap a direct service_role insert could otherwise exploit to create a lineage-less journal, live-forced during this checkpoint''s own investigation.';

create trigger finance_journals_validate_source
  before insert or update on app.finance_journals
  for each row
  execute function app.validate_finance_journal_source();

revoke execute on all functions in schema app from public;
