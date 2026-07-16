# Observability exporter/backend unavailable — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** Support, DevOps/on-call — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps
**Since:** Phase 0 (`CG-S5-PH0-014`, Prompt 93)
**Severity class:** Low today (no production exists to page on); becomes an operational Sev3–Sev4 once Phase 1's real export is wired — this document is the pre-committed contract, not a retroactive account of a real incident.

> `NOT_YET_REHEARSED` — this runbook describes the *designed* safe-degrade behavior (`scripts/observability/logger.ts`, proven by real failure-injection tests, `docs/standards/OBSERVABILITY_STANDARDS.md` §8/§9) rather than a rehearsal against a live Better Stack outage, because no real export exists yet (`ADR-0009`'s Propagation section — Phase 1 wires `@vercel/otel` once `app/` exists). Rehearsal is required before this graduates past `NOT_YET_REHEARSED` (§7).

## 1. Symptom / trigger

Once Phase 1 wires real export: the Better Stack ingestion endpoint is unreachable, rate-limits, or returns a sustained error — detected via the exporter's own error/retry telemetry (OpenTelemetry SDK export-failure counter) or a gap in the "Application health" dashboard (`docs/standards/OBSERVABILITY_STANDARDS.md` §1). Today (Phase 0): the equivalent local symptom is `scripts/observability/logger.ts`'s primary sink (`console.log`) throwing — exercised directly by `logger.test.ts`'s "falls back to the fallback sink when the primary sink throws" and "never rethrows even when both ... throw" tests.

## 2. Impact

**By design, none to the actual request/job/transaction** — `scripts/observability/logger.ts`'s safe-degrade rule (`docs/standards/OBSERVABILITY_STANDARDS.md` §8) means a telemetry failure never blocks, fails, or delays the caller. Impact is confined to reduced *observability* during the outage window: dashboards/alerts (§1 of the same document) may show a gap, and any Sev1 condition that would have paged (e.g. cross-tenant policy test failure, §1's "immediate Sev1" alert) could be delayed until export recovers — this is the one real risk worth escalating on, not a false "everything is fine" reading of a quiet dashboard.

## 3. Diagnosis steps

1. Confirm the application itself is healthy independent of telemetry — check `/api/health`/`/api/ready` (contract fixed in `docs/standards/OBSERVABILITY_STANDARDS.md` §7, implemented Phase 1) rather than inferring app health from an absent dashboard signal.
2. Check the exporter's own failure log — `scripts/observability/logger.ts`'s fallback sink writes to `stderr` on primary-sink failure; in Phase 1's real deployment this is the platform's own stdout/stderr capture (Vercel function logs), which remains available even when the *export* to Better Stack fails, since it is a local, always-on fallback, not a second remote dependency.
3. Check Better Stack's own status page for a vendor-side outage vs. a local configuration/credential issue (expired/rotated ingestion token, network egress block).

## 4. Resolution steps

1. If vendor-side: no action beyond monitoring the vendor's status page — the safe-degrade design (§2) means no user-facing action is required while waiting.
2. If credential/configuration-side (Phase 1): rotate/restore the ingestion token per `scripts/env/schema.ts`'s server-only secret classification pattern (`ADR-0003`) and redeploy.
3. **Rollback procedure if resolution fails:** none needed at the application layer — the feature degrades safely by design (§2); "rollback" here means reverting a bad *configuration* change (e.g. a botched ingestion-endpoint URL update) via the normal deploy-rollback path (`docs/architecture/11_DEVOPS_WORKSTREAM.md` §4), not a data or schema rollback.

## 5. Communication

Today (Phase 0): none required — no production exists. Phase 1: notify DevOps/on-call channel if the outage exceeds the RPD-025-adjacent window where a real Sev1 alert could have been missed (§2); no customer-facing communication is warranted for an observability-only gap with zero transactional impact.

## 6. Post-incident

Once real: confirm no Sev1-class condition (§1's 8 named alerts) occurred and went unpaged during the gap by reviewing the affected window's logs once export recovers (`correlation_id`-threaded, `docs/standards/OBSERVABILITY_STANDARDS.md` §2) — if one did, that is the real incident, handled under its own runbook, not this one. Record actual outage duration and whether the safe-degrade design held as designed.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| 2026-07-15 | Rehearsal (unit-level failure injection, not a live vendor outage) | Safe-degrade held: primary-sink throw → fallback sink used; both throw → no exception propagates to caller | `scripts/observability/logger.test.ts` — "emit — safe-degrade rule" suite, 3/3 passing |

A live-vendor-outage rehearsal (simulating a real Better Stack unreachability against the actual Phase 1 `@vercel/otel` wiring) is required before this runbook can be marked fully rehearsed — tracked as a Phase 1 downstream item, not claimed complete here.

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-07-15 | 0.1.0 | Initial — instantiated from `SUPPORT_RUNBOOK_TEMPLATE.md` at `CG-S5-PH0-014` | Claude Code (runtime build agent) |
