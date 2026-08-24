-- HDN-376 (Step 15, Prompt 376, API Compatibility Audit) -- Tier C adversarial review
-- fix pass. Four independent parallel Tier C lenses (correctness re-derivation;
-- schema-wide completeness sweep for the same defect classes; ledger/documentation
-- consistency; attack-surface adversarial testing) ran against the first-round commit
-- (`86bcab8`).
--
-- ===========================================================================
-- Ledger/documentation-consistency lens finding -- `app.verify_third_party_provider_
-- webhook_signature`'s own comment (added by this checkpoint's first-round migration,
-- 20260813000000) mislabeled this prompt as "HDN-376 (Data Lineage/API Compatibility
-- Audit)" -- "Data Lineage Audit" is HDN-375's own name (the prior checkpoint), never
-- this one's. Every other citation of HDN-376 in this checkpoint's own build log,
-- ledgers and the sibling function's own comment correctly say "API Compatibility
-- Audit" only -- an isolated copy/merge error, but a real one, and it was baked into
-- the applied schema comment itself, not merely prose. Corrected here rather than left
-- standing, since a `comment on function` restatement is itself additive (no schema
-- change, no behavior change) and does not edit the original migration file.
-- ===========================================================================

comment on function app.verify_third_party_provider_webhook_signature is
  'ATW-226E: ADR-0011''s own HMAC-SHA256-over-"<timestamp>.<payload>" scheme plus 5-minute timestamp-tolerance replay window. Fails closed to false for every reason (stale/null timestamp, null/empty signature, unknown/non-webhook connection, mismatched signature) -- never raises, so a caller-distinguishable error class/timing never leaks to an unauthenticated provider. HDN-376 (API Compatibility Audit): a null p_signature previously evaluated `v_expected = null` to SQL NULL, which `if not verify_...()` silently treats as verified rather than rejected -- live-forced, fixed by an explicit null/empty guard mirroring app.verify_logistics_partner_webhook_signature/app.verify_finance_payment_webhook_signature''s own already-proven pattern.';

revoke execute on all functions in schema app from public;
