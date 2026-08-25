# Performance and capacity evidence — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** DevOps/on-call, Engineering leads evaluating a capacity/scaling question — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps
**Since:** Phase 15 (`HDN-379`, Prompt 379 Performance and Scalability; consolidated at `HDN-388`, Prompt 388 Documentation Handoff)
**Severity class:** **Not incident-shaped, and not a completed capacity plan.** This runbook is a reference for "what performance/capacity evidence exists today, what does not, and how to generate more" — it does not certify any production, pilot, GA, or market-ready capacity commitment (RPD-001/034/036). Real, load-bearing evidence exists for a bounded Phase 5 slice; a large, honestly-disclosed evidence gap exists for everything built since (Phase 8/9, ~34 capabilities). Treat every figure in this document as sandbox/seeded-volume evidence, never a production SLA.

> Adapted from the single-incident-shaped template: §1/§3/§4 below describe "how to obtain performance evidence" (a repeatable procedure), not a single alert/trigger. §7 tracks completed evidence-gathering runs, not incident drills.

## 1. Symptom / trigger

Consult this runbook whenever someone asks "do we have evidence CargoGrid can handle X load/volume?", is evaluating a capacity or scaling decision (`docs/architecture/11_DEVOPS_WORKSTREAM.md` §9.1/§9.3), or is about to onboard a tenant whose expected data volume is materially larger than what has been tested. There is no automated alert that fires this runbook — it is a reference document, consulted deliberately, not a response to a detected condition.

## 2. Impact

None by itself — this document does not change runtime behavior. Its purpose is to prevent two failure modes: (a) someone asserting capacity confidence this repository has not actually earned, and (b) someone missing evidence that does exist because it is scattered across a build log, a results file, and `KNOWN_ISSUES.md`.

## 3. Diagnosis steps — what evidence exists today

**1. The one rigorously re-measured performance number in this repository is a test-infrastructure fix, not a product/application metric — do not cite it as an application capacity figure.** At `HDN-379` (Prompt 379, Performance and Scalability), `scripts/db-tests/rbac-enforcement.sql`'s ATW-032/`ISS-2026-032` actor-identity call-graph sweep (an O(n²) self-join test query, not shipped product code) was rewritten to O(n). This was measured with a same-schema matched-pair methodology (original and rewrite run in the same transaction, against the same disposable database, no rebuild in between — closing the "accept-on-faith" gap a naive before/after-rebuild comparison would carry):

   - First-round measurement: **692,092.8ms** (~11.5 min) original → **556.4ms** rewrite.
   - **Independent same-schema re-measurement at `HDN-379`'s own Tier C review — the figure this document treats as authoritative**: **212,105.6ms** (~3.5 min) original → **676.8ms** rewrite, **≈313× speedup**.
   - Both measurements are real; per `HDN-379.md` §13.1/§13.6, the ~3× spread in the ORIGINAL query's own cost reflects real sandbox contention/load variance at measurement time, not a methodology flaw — the rewrite's own cost stayed close both times (556ms vs. 677ms). `HDN-379.md` itself instructs citing this as "a real, massive (300×–1200×+) correctness-preserving speedup," never a single precise multiplier. After a further Tier C hardening pass restored two dropped safety properties (a word-boundary anchor and a real join-against-`fn` requirement), the hardened query re-timed at **1.66 seconds** — still ~128–417× faster than either original measurement.
   - **Why this belongs in a capacity runbook despite being test-infrastructure**: it is this repository's own best-documented example of "how a real O(n²)→O(n) fix is measured and verified here" (same-schema matched-pair methodology, re-verified independently, timing variance disclosed rather than hidden) — the same discipline any future application-level performance fix should follow. It is **not** evidence about any user-facing route or RPC's own latency.

**2. Real, load-bearing load-test evidence exists for a bounded Phase 5 slice only.** `scripts/load-tests/run.sh` is a genuine, working 8-scenario harness (`pgbench`-based concurrency tests plus a Node.js GPS-telemetry load generator), built at `CG-S10-ATW-024` (Prompt 243, Phase 5) to close `ISS-2026-014`. Its scope is exactly: inventory movement (`app.post_inventory_movement`, shared-balance row-lock contention), WMS pick/putaway claim (`app.claim_wms_pick_task`/`app.claim_wms_putaway_task`), the generic job queue (`app.claim_next_job` backlog drain plus dead-letter/replay reconciliation), GPS telemetry ingestion, and the 4 ATW-023 customer-inventory RPCs' own pagination `EXPLAIN` evidence. The one committed results file, `scripts/load-tests/results/RESULTS_CG-S10-ATW-024.txt`, is dated **2026-08-05**, captured against a **137-migration** build (today: 329 migrations) — real numbers from that run, cited here directly from the file, never re-derived or rounded:

   | Scenario | Result | Measured |
   |---|---|---|
   | 1 — concurrent `post_inventory_movement` (shared balance) | PASS — 13,464 concurrent posts, no lost update, no negative `on_hand` | latency: n=13464, p50=15.523ms, p95=63.941ms, p99=99.607ms, max=177.232ms |
   | 2a/2b — concurrent WMS pick/putaway claim | PASS — 500/500 tasks claimed exactly once each, zero double-claims (audit-log verified), zero left unclaimed | claim latency (combined): n=1200, p50=6.437ms, p95=15.51ms |
   | 3 — `claim_next_job` backlog drain | PASS — full 5,000-job backlog drained, no lost/double-claimed jobs | queue-age percentiles captured in the results file |
   | 3d — dead-letter + replay reconciliation | PASS — 10 jobs genuinely dead-lettered, replayed via `app.requeue_dead_letter_job`, all completed, reconciled counts match | — |
   | 4 — GPS telemetry ingestion (real TCP + Codec 8 Extended simulator) | PASS | ack latency: p50=3.012ms, p95=4.886ms, p99=5.154ms |
   | 7 — restart/recovery (real `SIGKILL` mid-transaction + real Postgres cluster restart) | PASS — idempotency-key retry after recovery returns the original committed result, no double-apply; exactly 1 row for the committed key across both calls | exactly-once confirmed |
   | 8 — concurrent multi-source telemetry arbitration | PASS | — |

   `HDN-379.md` §1 independently re-ran this same harness end to end this checkpoint ("still runs clean end to end with real measured p50/p95/p99 latencies, zero double-claims, zero lost updates, exactly-once idempotency proven via a real `SIGKILL`+restart") and confirmed it still passes — it did not re-capture a fresh results file, so the committed numbers above remain the ones dated 2026-08-05/137-migrations.

**3. A large, honestly-disclosed evidence gap exists for everything built since — this is the load-bearing fact of this runbook, not a footnote.** Three registered, `OPEN`/`ACCEPTED`-shape findings in `docs/runtime/KNOWN_ISSUES.md`, each independently re-verified rather than merely repeated:

   - **`ISS-2026-141`** (Phase 8, Medium, `OPEN`) — zero load/performance-test evidence exists for any Phase 8 route or RPC (Customer Portal, Loyalty — ~30 routes, ~120 RPCs) at a declared target volume. `scripts/load-tests/results/RESULTS_CG-S10-ATW-024.txt` predates Phase 8's own migration range entirely and does not cover it. A surface-level-similar script, `pagination-explain.sh`, was independently confirmed to target only pre-Phase-8 (Phase 5, ATW-023) functions, not Phase 8's differently-named `app.list_customer_portal_inventory_balances` family — not Phase 8 evidence, despite the naming similarity.
   - **`ISS-2026-148`** (Phase 9, Medium, `OPEN`) — the identical gap, one phase later: zero load/performance-test evidence exists for any Phase 9 route or RPC (Reporting Engine, dashboard builder, materialized-view refresh, scheduled reports, automation rule engine, the whole `/api/v1` surface, webhook delivery worker, AI-governed dispatch, enterprise IAM/monitoring/DR) at any declared target volume.
   - **`ISS-2026-238`** (`HDN-379`, Medium, `OPEN`) — 4 production routes load an entire tenant-wide dataset to the browser with **zero pagination**, live-verified via real `EXPLAIN (ANALYZE, BUFFERS)` at a seeded 25,000/10,000-row volume: `listAccounts` and `listCustomerContracts` (`server/queries/account.ts:29`, `server/queries/contract.ts:31`, 9.9ms/455 buffers and 3.9ms/194 buffers at that seeded volume — fast today, but cost and payload size scale linearly with tenant data volume with no cap), `listQuotationsForTenant` (`server/queries/quotation.ts:68`, same shape), and (reclassified Medium at Tier C) `listFilesForTenant` (`server/queries/document.ts:38`, a polymorphic transactional-volume attachment table). A Tier C completeness sweep additionally found `app/(tenant)/[tenantSlug]/operations/fleet/page.tsx` loads **4 unbounded whole-tenant lists in parallel** — `listVehicleOperationalProfiles`, `listDriverOperationalProfiles`, `listGpsDevices`, `listSimCards` (`server/queries/fleet-driver-device.ts`, lines 37/46/55/64) — graded Low-Medium (no live `EXPLAIN` evidence gathered for these 4, unlike the 3 originally-confirmed routes), plus ~12 further lower-severity siblings sharing the same code pattern (config/rule/rate/directory-shaped tables, naturally bounded by business cardinality). None of this is fixed — real pagination UI is required, not a silent query-layer cap, per `HDN-379.md`'s own explicit refusal to ship a "cosmetic partial fix."

   All three carry a named future owner ("a dedicated future performance-test-harness task") and none blocks this repository's own standing disposition rule for a disclosed, non-Critical/High evidence gap with a named owner.

## 4. Resolution steps — how to run what exists, and what a future capacity task must add

1. **To re-run the existing, real evidence**: `bash scripts/load-tests/run.sh` against a disposable Postgres (same `DATABASE_ADMIN_URL` convention as `scripts/db-tests/run.sh`) regenerates a fresh timestamped results file under `scripts/load-tests/results/` (gitignored) and can refresh the committed `RESULTS_CG-S10-ATW-024.txt`. This re-proves the Phase 5 scope only — it does not gain any Phase 8/9 coverage by construction, since the scenario scripts themselves target Phase 5 functions.
2. **To close `ISS-2026-141`/`148` for real** (not attempted by this runbook — a capability-sized addition, not a documentation fix): extend `scripts/load-tests/` with new scenarios covering Phase 8 (Customer Portal/Loyalty) and Phase 9 (Reporting, dashboards, automation, `/api/v1`, webhooks, AI dispatch, enterprise IAM) routes/RPCs, at a real declared environment/dataset/concurrency profile, following the same convention already established (`pgbench`-based concurrency scripts plus `EXPLAIN (ANALYZE, BUFFERS)` evidence) rather than introducing a second tooling family (no `k6` or other dedicated HTTP load-testing tool exists anywhere in this repository today — confirmed by repository-wide grep at `HDN-379`/prior).
3. **To close `ISS-2026-238` for real**: build real pagination UI (cursor state, a count query, a `Pagination` control) for `commercial/accounts`, `commercial/quotations`, `commercial/contracts` first (the 3 confirmed transactional-volume cases plus `listFilesForTenant`), then the fleet-assets page's 4 unbounded lists, then audit the ~12 lower-severity siblings for whether their bounded cardinality genuinely makes pagination unnecessary.
4. **Never** silently truncate an unbounded list with a query-layer `.limit()` as a stand-in fix — this repository's own discipline treats a silent truncation with no UI indication as worse than the current unbounded-but-honest behavior (`HDN-379.md` §1).

Rollback procedure if a future load-test/pagination change fails: none specific to this runbook — any schema/query change made while pursuing the above follows the normal migration-rollback path (`docs/runbooks/deployment-migration-guard.md`, `docs/architecture/11_DEVOPS_WORKSTREAM.md` §4.4).

## 5. Communication

No customer-facing or SLA communication is warranted from this document alone — it records evidence status, not an incident. If a capacity question arises for a specific prospective tenant (e.g. "can this tenant's expected data volume be supported"), escalate per `docs/architecture/11_DEVOPS_WORKSTREAM.md` §8.4's support-tier table (see `docs/runbooks/on-call-ownership.md`) rather than answering from this document's own figures alone — none of the evidence here is at production scale.

## 6. Post-incident / post-evidence-run

Record, for any future load-test run: the exact scenario scope, the migration count/date at time of run (evidence goes stale as the schema grows — the committed 137-migration results file is already 192 migrations behind current `HEAD`), and whether any threshold from `docs/architecture/11_DEVOPS_WORKSTREAM.md` §9.1/§9.3 (DB CPU/connection saturation, the 2-second slow-query threshold, queue-depth/oldest-job-age SLA) was exercised or breached.

## 7. Rehearsal history

| Date | Type | Outcome | Evidence |
|---|---|---|---|
| 2026-08-05 | Load test — `CG-S10-ATW-024`, Phase 5 scope, 137 migrations | **PASS**, all 8 scenarios — see §3 item 2 table above | `scripts/load-tests/results/RESULTS_CG-S10-ATW-024.txt` |
| 2026-08-24 (`HDN-379`) | Re-run of the same 8-scenario harness, current schema (328 migrations) | **PASS**, confirmed clean end to end; no fresh results file captured (numbers above remain the 2026-08-05 figures) | `docs/build-log/full-system-hardening/HDN-379.md` §1 |
| 2026-08-24 (`HDN-379`) | Test-infrastructure O(n²)→O(n) rewrite, matched-pair + independent Tier C re-measurement | **RESOLVED** (`ISS-2026-145`) — see §3 item 1 | `docs/build-log/full-system-hardening/HDN-379.md` §1, §13.1, §13.5 |
| — | Phase 8/Phase 9 load/performance evidence | **Not run — disclosed gap, `ISS-2026-141`/`148`, `OPEN`** | `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-141`/`148` |

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-24 | 0.1.0 | Initial — instantiated from `SUPPORT_RUNBOOK_TEMPLATE.md` at `HDN-388` (Step 15 Full-System-Hardening, Documentation Handoff), consolidating existing evidence from `HDN-379.md` and `docs/runtime/KNOWN_ISSUES.md` (`ISS-2026-141`/`148`/`238`) into a dedicated reference. No new measurement taken by this checkpoint — every figure above is quoted from an already-existing source, cited inline. | Claude Code (runtime build agent) |
