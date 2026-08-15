-- Bounded, additive verification-defect repair from the Prompt 294 (HRIS and
-- Ticketing Integrated Verification, CG-S12-HRT-022) checkpoint, per
-- docs/ai-agent-build-prompt-package/12-phase-07-hris-ticketing/294_HRIS_
-- TICKETING_INTEGRATED_VERIFICATION_PROMPT.md section 13 ("allow only
-- minimal registered verification-defect repair") and the orchestrating
-- synthesis's own explicit charter, which names a missing index as a valid
-- in-checkpoint repair category. Full finding, live reproduction, and
-- disposition reasoning are in docs/build-log/phase-07/HRT-294.md and
-- docs/runtime/KNOWN_ISSUES.md (ISS-2026-113). Additive only -- zero lines
-- of any prior migration (<= 20260731210000) touched.
--
-- ===========================================================================
-- FIX -- app.list_tickets/app.list_my_tickets (HRT-286,
-- supabase/migrations/20260731060000_create_ticketing_internal.sql:1831-1917)
-- both filter on tenant_id and order by (created_at desc, id desc), but the
-- only index matching that ORDER BY, tickets_created_at_idx (same file,
-- line 449), carries no tenant_id column -- so the planner walks the
-- GLOBAL cross-tenant timeline with tenant_id/status applied as a Filter,
-- rather than seeking directly to the target tenant's own rows. Live-
-- reproduced during HRT-294 (disposable database, 68,010-row app.tickets
-- fixture: one tenant's 8,010 rows moved to a quiet historical window while
-- a 60,000-row "noise" tenant stayed recent): the identical list_tickets
-- query shape went from 1,829 buffer reads / 4.3ms (both tenants recent) to
-- 129,798 buffer reads / 52ms (~71x I/O) for one 50-row page, still via
-- Index Scan using tickets_created_at_idx with tenant_id/status as a
-- post-scan Filter -- correct results, but a genuinely realistic
-- ("tenant that hasn't been active lately") multi-tenant workload degrades
-- sharply. Mirrors this repository's own established remediation for the
-- identical shape (ISS-2026-056, app.list_vendor_contracts, Prompt 269
-- Hardening): a covering composite index matching the RPC's own exact
-- (tenant_id, created_at desc, id desc) filter+sort shape. No CONCURRENTLY
-- anywhere in this repository's own migrations (confirmed by grep); this
-- migration matches that established convention.
-- ===========================================================================

create index tickets_tenant_created_idx on app.tickets (tenant_id, created_at desc, id desc);

comment on index app.tickets_tenant_created_idx is
  'HRT-294 (ISS-2026-113): covering index for app.list_tickets/app.list_my_tickets own (tenant_id = ... order by created_at desc, id desc) shape -- without it the planner falls back to the tenant_id-less tickets_created_at_idx and walks the global cross-tenant timeline. Purely additive, zero behavior change to any RPC -- mirrors ISS-2026-056''s own vendor_contracts_tenant_created_idx fix exactly.';
