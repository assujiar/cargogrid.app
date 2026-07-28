# Phase 3 (Operations) → Phase 4/5/8 Entry Package

**Produced by:** `CG-S8-OPS-021` (Prompt 187 — Operations Documentation and Handoff)
**Audience:** an independent Phase 4 (Finance)/Phase 5 (Advanced TMS/WMS)/Phase 8 (Customer Portal) agent with **zero prior context** from this build session — every fact below is either directly cited to a `VERIFIED` document or explicitly marked as this checkpoint's own reconciliation.
**Status of this package itself:** complete pending one external precondition — `CG-S8-OPS-022` (Prompt 188, Phase 3 Closure Verification) has not yet run. **Nothing in this document should be read as `PHASE_3_VERIFIED` being set** — only Prompt 188 may set that.

This is a **new, self-contained artifact**, distinct from `docs/runtime/HANDOFF.md` (the intra-Phase-3, checkpoint-to-checkpoint runtime handoff). This package exists specifically for the "fresh Phase 4/5/8 agent reconstructs Operations and starts the exact eligible next task safely" flow, mirroring `docs/build-log/phase-01/PLATFORM_CORE_HANDOFF_PACKAGE.md` and `docs/build-log/phase-02/COMMERCIAL_HANDOFF_PACKAGE.md`'s own precedent two phases up.

## 1. Verified dependencies (what Phase 4/5/8 may rely on as fact)

| Closure | Status | Evidence |
|---|---|---|
| Phase 0 — Discovery and Foundation | `PHASE_0_VERIFIED` | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |
| Phase 1 — Platform Core | `PHASE_1_VERIFIED` | `docs/build-log/phase-01/PLATFORM_CORE_CLOSURE_REPORT.md` |
| Phase 2 — Commercial | `PHASE_2_VERIFIED` | `docs/build-log/phase-02/COMMERCIAL_CLOSURE_REPORT.md`, `COMMERCIAL_HANDOFF_PACKAGE.md`, `JOB_ORDER_HANDOFF_CONTRACT.md` |
| Operations kickoff (`167`, `CG-S8-OPS-001`) | `VERIFIED` | `docs/build-log/phase-03/00_OPERATIONS_WBS.md`, `OPERATIONS_EXECUTION_INDEX.md` row `001` |
| 17 Operations capability tasks (`168`–`184`, `CG-S8-OPS-002..018`) | All `VERIFIED` | `docs/runtime/TASK_LEDGER.md`; individual build logs `docs/build-log/phase-03/OPS-168.md`–`OPS-184.md` |
| Integrated Operations Verification (`185`, `CG-S8-OPS-019`) | `VERIFIED` | `docs/build-log/phase-03/OPS-185.md` |
| Tenant/Security/Financial/Data Hardening (`186`, `CG-S8-OPS-020`) | `VERIFIED` | `docs/build-log/phase-03/OPS-186.md` |
| Operations Documentation and Handoff (`187`, `CG-S8-OPS-021`, this checkpoint) | `IN_PROGRESS` → `VERIFIED` on this checkpoint's own close | This document + `docs/build-log/phase-03/OPS-187.md` |
| Phase 3 Closure Verification (`188`, `CG-S8-OPS-022`) | `NOT_STARTED` — the one remaining gate before `PHASE_3_VERIFIED` | `188_OPERATIONS_CLOSURE_VERIFICATION_PROMPT.md` |

**Domain-code status:** zero Finance/Procurement/Advanced-TMS-WMS/Customer-Portal (or any later-phase) business code exists anywhere in this repository. Everything listed in §2 below is Operations-domain evidence — Operations' own scope ends at the surfaces named in §3 below; no Finance ledger/AR/GL table, no Advanced TMS/WMS multi-leg/route-planning/warehouse table, and no live Customer Portal route exists anywhere.

## 2. Preserved assets (what already exists — do not recreate)

### 2.1 Database (19 Operations migrations of 71 total, `supabase/migrations/`)

Every migration lives under `app` schema ownership, RLS enabled on every tenant-scoped table, and the `ERR-2026-004` per-migration convention (`revoke execute on all functions in schema app from public;`) present in every migration since `PLT-118` and independently re-confirmed across all 71 migrations at `OPS-185`'s own integrated-verification checkpoint and `OPS-186`'s own hardening sweep.

| Capability | Migration | Key tables/functions |
|---|---|---|
| Operations WBS/Kickoff (`167`) | — (planning only, zero schema) | `docs/build-log/phase-03/00_OPERATIONS_WBS.md` |
| Job Order (`168`) | `20260727090000_create_operations_job_order.sql` | `app.job_orders`, `app.job_order_overrides`, `prepare_job_order` (record-scope-hardened at `OPS-186`), `confirm_job_order`, `override_job_order_field` |
| Shipment Order (`169`) | `20260727100000_create_operations_shipment_order.sql` | `app.shipment_orders`, `create_shipment_order_from_job` (record-scope-hardened at `OPS-186`), `confirm_shipment_order`, `cancel_shipment_order`, `get_job_shipment_allocation_balance` |
| Shipment Lifecycle (`170`) | `20260727110000_create_operations_shipment_lifecycle.sql` | `app.shipment_status_transitions`, `transition_shipment_order`, `get_shipment_status_history` |
| Land/Air/Sea Baseline (`171`) | `20260727120000_create_operations_mode_baseline.sql` | `app.shipment_mode_profiles`, `set_shipment_mode_profile`, `change_shipment_mode` |
| Resource/Vendor Assignment (`172`) | `20260727130000_create_operations_resource_assignment.sql` | `app.resource_assignments`, `assign_resource`/`hold_resource_assignment`/`reassign_resource` |
| Milestone Management (`173`) | `20260727140000_create_operations_milestone_management.sql` | `app.milestone_codes` (platform-wide catalogue), `app.milestone_events`, `app.shipment_milestone_projections`, `ingest_milestone_event` |
| Exception and Escalation (`174`) | `20260727150000_create_operations_exception_escalation.sql` | `app.operational_exceptions`, `app.exception_sla_policies`, `report_exception`/`escalate_exception`/`resolve_exception` |
| Basic Dispatch (`175`) | `20260727160000_create_operations_basic_dispatch.sql` | `app.dispatch_commands`, `evaluate_dispatch_readiness`, `dispatch_shipment_order`, `bulk_dispatch_shipment_orders` |
| Document Requirement (`176`) | `20260728090000_create_operations_document_requirement.sql` | `app.document_requirement_definitions`, `app.shipment_document_checklist_items`, `pin_shipment_document_checklist` |
| ePOD Capture and Review (`177`) | `20260728100000_create_operations_epod_capture_review.sql` | `app.epod_captures`, `start_epod_capture`/`submit_epod_capture`/`complete_epod_capture` |
| Actual Cost (`178`) | `20260728110000_create_operations_actual_cost.sql` | `app.shipment_actual_costs`, `app.shipment_actual_cost_components`, `create_actual_cost_draft`/`decide_actual_cost` |
| Basic Job Profitability (`179`) | `20260728120000_create_operations_job_profitability.sql` | `app.job_profitability_snapshots` (`>= 0` constraints on revenue/cost hardened at `OPS-186`), `calculate_job_profitability`, `has_view_job_margin` |
| Basic Public Customer Tracking (`180`) | `20260728130000_create_operations_public_tracking.sql` | `app.shipment_tracking_tokens`, `issue_shipment_tracking_token`, `lookup_public_shipment_tracking` (the one deliberate `anon` grant) — **the Phase 8 handoff contract, §3.3** |
| Billing Readiness (`181`) | `20260728140000_create_operations_billing_readiness.sql` | `app.billing_readiness_evaluations`, `app.billing_readiness_handoffs`, `evaluate_billing_readiness`, `handoff_billing_readiness` — **the Phase 4 handoff contract, §3.1** |
| Operations Dashboard (`182`) | `20260728150000_create_operations_dashboard.sql` | 6 `app.get_ops_dashboard_*` read functions, zero new table |
| Operations Reports (`183`) | `20260728160000_create_operations_reports.sql` | 6 new `app.report_types` rows, `enqueue_ops_report_export` (queues only, no live worker) |
| Operations Transaction Lineage (`184`) | `20260728170000_create_operations_transaction_lineage.sql` | `app.transaction_lineage_edges`, 6 `AFTER INSERT` triggers, `get_transaction_lineage`, `record_transaction_lineage_override` (record-scope-hardened at `OPS-185`), `detect_transaction_lineage_anomalies` (bounded record-scope-hardened at `OPS-186`), `backfill_transaction_lineage` |
| Integrated Verification hardening (`185`) | `20260728180000_harden_operations_transaction_lineage_override.sql` | `CREATE OR REPLACE FUNCTION app.record_transaction_lineage_override` — zero new table |
| Security/Financial Hardening (`186`) | `20260728190000_harden_operations_security_financial.sql` | `CREATE OR REPLACE FUNCTION` on 3 functions + 2 new `job_profitability_snapshots` check constraints — zero new table |

**Integrated Operations Verification (`185`) introduces zero new table** — its own migration is a hardening fix discovered by its cross-capability test, not a feature schema addition; **Documentation and Handoff (`187`, this checkpoint) introduces zero migration** — documentation-only, per its own mandate.

### 2.2 Application code (`app/`, `server/` — Operations' own additions on top of Commercial's Phase 2 foundation)

- **`server/contracts/<domain>/`** — Zod schemas for every one of the 17 Operations capabilities' own public shape, including `server/contracts/billing-readiness/billing-readiness.ts` (the exact `BillingReadinessEvaluation`/`BillingReadinessHandoff` shape Phase 4 must consume, §3.1) and `server/contracts/transaction-lineage/transaction-lineage.ts` (the full quote-to-billing lineage manifest shape).
- **`server/queries/`/`server/mutations/`** — typed client wrappers per capability, same two-client architecture (`authenticated` RLS-scoped vs. `service_role`) Platform Core/Commercial established.
- **`app/(tenant)/[tenantSlug]/operations/`** — the full Operations portal: `job-orders/`, `shipment-orders/`, `dispatch/`, `dashboard/`, `reports/`. The Job Order detail page (`job-orders/[jobOrderId]/page.tsx`) is the one page every Operations capability's own panel converges on (profitability, billing readiness, transaction lineage panels all live here).
- **`app/(public)/tracking/[token]/`** — the third public, unauthenticated route this repository adds (after `/login` and `/quote-decision/[token]`) — the customer-facing shipment tracking surface (`OPS-180`) — **the Phase 8 handoff contract, §3.3**.
- **`lib/portal/operations-guard.ts`/`resolve-operations-access.server.ts`** — the Operations portal-entry guard, mirroring Commercial's own guard shape.

**No REST/GraphQL live HTTP route exists anywhere** — unchanged since Platform Core (`PLT-130` remains a contract/logging foundation only).

### 2.3 Verification and hardening evidence (`scripts/db-tests/`, 72 files)

53 Platform-Core/Commercial files (unchanged) plus 19 Operations files, 17 individual-capability files (each independently exhaustive for its own scope) plus two Operations cross-cutting files: `operations-integrated-verification.sql` (`OPS-185`, one fixture driven through the complete critical flow across all 17 capabilities, cross-checked against the Dashboard/Reports/Lineage read paths, the discovery site for `OPS-185`'s own finding) and `operations-security-financial-hardening.sql` (`OPS-186`, one targeted root-cause test per finding). All passing together against one disposable, sequentially-migrated database in a single `pnpm run db:test` invocation.

### 2.4 ADRs

No new ADR was ratified during the Operations phase (`168`–`186`) — every architectural decision Operations needed (schema ownership, RLS/RBAC evaluation, versioning discipline, audit trail) was already resolved by Platform Core/Commercial's own 18 ratified ADRs (`ADR-0001`–`ADR-0018`, see `docs/adr/README.md` §6). Operations reused every one of these directly rather than re-deciding anything (e.g. the same `app.evaluate_permission`/`app.can_access_record`/`app.capture_audit_event` primitives Commercial already established).

## 3. The three downstream handoff contracts (Prompt 187 §20 task 3 — the primary deliverable of this checkpoint)

See the dedicated companion document: **`docs/build-log/phase-03/OPERATIONS_DOWNSTREAM_CONTRACTS.md`** — covering all three surfaces Operations exposes to later phases in one file (a bounded scope decision, disclosed in that document's own header, since Operations extends existing tables for Phase 5 rather than producing a separate snapshot contract the way Commercial's Job Order handoff does):

- **§1 — Phase 4 (Finance) Billing Readiness contract**: the exact `BillingReadinessEvaluation`/`BillingReadinessHandoff` shape, the `evaluate_billing_readiness`/`handoff_billing_readiness` API, compatibility notes, and the unresolved-dependency list Phase 4 must resolve.
- **§2 — Phase 5 (Advanced TMS/WMS) extension boundaries**: which Operations tables/functions Phase 5 is expected to extend in place (Shipment Order, mode profiles, resource assignments, milestone events) versus which it must build fresh (multi-leg/multi-modal routing, warehouse inventory, capacity/route planning) — no snapshot handoff exists here, since Phase 5 is a direct schema extension of Phase 3's own tables, not a downstream consumer of an immutable record.
- **§3 — Phase 8 (Customer Portal) Public Tracking contract**: the exact `lookup_public_shipment_tracking` sanitized projection shape, the token-issuance API, rate-limiting behavior, and what a real Customer Portal must still build on top of this one RPC.

## 4. Known issues carried into Phase 4/5/8 (from `docs/runtime/KNOWN_ISSUES.md`, current state — unchanged since the Phase 2→3 handoff)

| ID | Status | Carries into Phase 4/5/8 as |
|---|---|---|
| `ISS-2026-005` | `OPEN`, Low | A documentation-completeness gap in `CHANGE_MANIFEST.md` (Prompts 83–90 entries never backfilled, Phase 0-scoped) — does not affect Operations or any later code/schema/decision; owner DevEx, pick up opportunistically |
| `ISS-2026-007` | `OPEN`, Medium | No working automated dependency/supply-chain audit gate (`pnpm audit` calls a retired npm endpoint) — `pnpm install --frozen-lockfile` remains the real, working deterministic-install control in the interim |
| `ISS-2026-006` | `ACCEPTED_RISK`, Low | 4 historical citations to deleted plural build-log paths, excused via a named allowlist — no action needed |
| All others (`ISS-2026-001..004`, `008`) | `RESOLVED` | No action needed |

**Zero new issue was opened anywhere across the entire Operations phase** (`OPS-167`–`186`, 20 checkpoints). **No Critical or unresolved High-severity issue exists** — the several findings found during `OPS-182`/`OPS-184`/`OPS-185`/`OPS-186`'s own authoring/verification/hardening work are all fully closed within the same checkpoint that found them, never left open. Neither open issue blocks any Phase 4/5/8 gate or decision.

**Errors:** `ERR-2026-001..004` all `RECOVERED`/`SUPERSEDED`, `ERR-2026-004`'s per-migration convention independently re-confirmed intact across all 71 migrations at `OPS-186`'s own audit sweep. **Zero `OPEN` error.**

## 5. Environment commands (verified working, this checkpoint)

```
pnpm install --frozen-lockfile   # deterministic install
pnpm run typecheck               # tsc --noEmit
pnpm run lint                    # eslint .
pnpm run test                    # node:test, scripts/**|server/**|lib/**|tests/**/*.test.ts
pnpm run test:e2e                # Playwright + axe-core (sandbox chrome-headless-shell gap, unchanged since PLT-117)
pnpm run db:test                 # bash scripts/db-tests/run.sh -- 71 migrations + 72 test files, disposable DB
pnpm run docs:check              # scripts/docs/check-doc-links.ts
pnpm run security:check          # scripts/security/check-secrets.ts
pnpm run data-classification:check
pnpm run threat-model:check
pnpm run standards:check         # scripts/standards/check-suppressions.ts
pnpm run git:check-paths         # scripts/git/check-protected-paths.ts (known false positive on any new migration file, see §6)
```

`db:test` requires a reachable Postgres with PostGIS available (`postgresql-<major>-postgis-3` locally; CI uses `postgis/postgis:17-3.4`). All gate results as of this checkpoint: see `docs/build-log/phase-03/OPS-187.md` §5 (live gate run) — do not treat any specific `node:test`/`db:test` count in this document as durable; read the live gate output.

## 6. Residual risks Phase 4/5/8 should be aware of (not blocking, all already-disclosed across OPS-168..186's own build logs)

- **Milestones are not modeled as a persisted lineage edge** (`OPS-184`'s own disclosed design decision) — a shipment can accumulate many milestone events, and persisting one edge per event would be an unbounded graph query. The transaction-lineage manifest folds in only the shipment's own current `app.shipment_milestone_projections` row (one bounded row per shipment) as a node attribute, not per-event history. Phase 5's own advanced visibility/tracking work must design its own event-level lineage if it ever needs one.
- **No FX/multi-currency conversion anywhere in Operations** — the same disclosed boundary Commercial's `app.calculate_margin` already carries (`COM-150`); `app.shipment_actual_costs`/`app.job_profitability_snapshots` both fail closed (`mixed_currency`/`unavailable`) rather than convert.
- **`app.create_shipment_order_from_job` (`OPS-169`) never stamps `org_unit_id` on the Shipment Order it creates** (only `owner_user_id`) — discovered at `OPS-182`'s own authoring, not fixed (it is a disclosed, accepted design boundary, not a security gap — only direct ownership or the Supreme Admin bypass grants shipment-level record-scope access, no same-team sharing is possible). Phase 5, if it ever needs team-based shipment sharing, must design that from scratch or retrofit this column.
- **Operations Reports' export path is queue-only** — `app.enqueue_ops_report_export` reaches `status=queued` and stops there; no live worker processes the `report_generation` job type anywhere in this repository (the same disclosed `NOT_RUN` condition every Platform Core/Commercial job type carries since `PLT-132`). Of the seven report subjects Prompt 183 §4 names, only the six `OPS-182`'s own dashboard already computes are implemented — profitability has no existing governed *summary* query to reuse, a disclosed gap.
- **`app.billing_readiness_evaluations.rule_version` is a fixed, disclosed placeholder (`1`)** — no configurable rule-engine table exists yet for billing-readiness evaluation rules (`OPS-181`'s own disclosed simplification, the same class as `OPS-179`'s "no FX conversion" boundary). Phase 4 (Finance) needing a configurable readiness rule set must design this from scratch.
- **`app.transaction_lineage_edges`'s `duplicate_target`/`cross_tenant_mismatch` reconciliation diagnostics remain deliberately tenant-wide** (`OPS-186`'s own disclosed, bounded fix) — both compare two edges that may belong to different owners/org units by definition, so no single record scope applies; only the two single-record orphan diagnostics are record-scope-filtered.
- **RPD-022** (Supreme Admin absolute CRUD) — unchanged from Platform Core/Commercial; no tamper-proof/immutability claim may ever be made anywhere in Operations either.
- **No live Supabase project exists anywhere** — unchanged from Platform Core/Commercial; a real sign-in flow, real RLS-against-a-live-database session, and real deploy pipeline all remain `NOT_RUN`.
- **`pnpm run test:e2e` has the same persistent, disclosed sandbox condition** since `PLT-117` — `chrome-headless-shell` executable missing. No Operations E2E-relevant spec was added (disclosed, not an oversight).
- **`git:check-paths` false-positives on any brand-new migration file** — reproduces identically at every Operations checkpoint that added one (`OPS-168..186`); not a real protected-path violation, disclosed at each occurrence.

## 7. Corrections made this checkpoint (disclosed, not hidden)

None found. This checkpoint's read-back of `docs/adr/README.md` §6, `docs/runtime/KNOWN_ISSUES.md`, and every Operations build log (`OPS-167`–`186`) found no stale citation, no missing evidence link, and no orphaned reference — `OPS-185`'s own integrated-verification checkpoint and `OPS-186`'s own hardening sweep already independently confirmed the schema/docs were internally consistent immediately before this checkpoint, and nothing changed in the interim.

## 8. Forbidden-scope confirmation (Prompt 187 §12/§24, re-checked this checkpoint)

`git ls-files app/ lib/ server/ components/ | grep -iE "invoice|payment|general_ledger|accounts_receivable|multi_leg|warehouse|inventory_ledger|route_plan|fleet_telematics|customer_portal"` returns **zero matches** (re-run directly this checkpoint) — zero Finance/Advanced-TMS-WMS/Customer-Portal (or any later-phase) domain concept exists anywhere in application code. Only the disclosed handoff *surfaces* named in §3 exist (billing-readiness evidence records, database-side; the public tracking RPC), never a Finance ledger table, an Advanced TMS/WMS multi-leg/warehouse table, or a live Customer Portal route.

## 9. Fresh-context reconstruction check (Prompt 187 §21/§28, rehearsed this checkpoint)

Reading only this document plus its cited paths (no other session context), an agent can determine: what phase the repository is in (Phase 3, pending Prompt 188 closure), what exists on disk (§2), the exact three contracts Phase 4/5/8 must consume and how (§3, companion document), what is decided vs. still open (§2.4, §6), what commands verify the current state (§5), what the exact next prompt is once Phase 3 formally closes (Prompt 188, `CG-S8-OPS-022` — already dependency-`READY` and authorized under this session's "lanjut sd prompt 188" extended range), and what residual risks/design boundaries to respect rather than "fix" without re-reading history first (§6). This satisfies Prompt 187 §21's "fresh Phase 4/5/8 agent reconstructs Operations and safely starts exact next task."
