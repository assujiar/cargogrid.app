# Prompt 248 — Advanced TMS/WMS Closure Verification

**Prompt ID:** `CG-S10-ATW-029`  
**Package document:** `CG-AABPP-ATW-248`  
**Version:** `0.11.0`  
**Runtime output:** `docs/build-log/phase-05/ADVANCED_TMS_WMS_CLOSURE_REPORT.md`

Do not begin until Prompt 247 is `VERIFIED`, the active checkpoint still carries `PHASE_4_VERIFIED`, and all Phase 5 capability, integrated-verification, hardening and handoff evidence is available for independent review.

## Objective

Independently verify Phase 5 Advanced TMS/WMS runtime completeness, transport/inventory integrity, tenant/customer security and readiness for Phase 6 Procurement/Vendor implementation.

## Required verification

1. Verify Prompts 220–247 at one repository/schema/environment checkpoint and reconcile every WBS, dependency, traceability and evidence link.
2. Confirm all 24 master Phase 5 capabilities have implementation, migration/contract/UI as applicable, tests, documentation and owner: multi-leg/multimodal shipment; dispatch board; fleet/driver; route/load planning; first/middle/last mile; GPS/telematics; capacity/utilization; advanced milestones/exceptions; warehouse/zone; bin/racking; inbound; receiving; putaway; inventory ledger; lot/batch/serial/expiry; picking; packing; outbound; cycle count/adjustment; label/barcode; warehouse billing; customer inventory access; high-volume controls; advanced claim/incident.
3. Confirm all 24 advanced anchors across `OPS-SHP-001..004`, `OPS-TMS-001..004`, `OPS-WMS-001..004`, `OPS-TRK-001..004`, `OPS-DOC-001..004` and `OPS-CST-001..004` map to durable runtime evidence with no orphan.
4. Prove canonical Phase 3/4 Shipment Order, customer, document, inventory and Finance contracts were extended without duplicate roots, silent re-entry or tenant-specific forks.
5. Prove multi-leg/multimodal planning → governed dispatch → fleet/driver/capacity assignment → first/middle/last-mile execution → scoped GPS/telematics → ordered milestone/exception → delivery/custody/claim evidence, including retries, stale data and recovery.
6. Prove the critical `Inbound → Receiving → Putaway → Inventory Ledger → Pick → Pack → Outbound` WMS flow, including `OPS-WMS-US-001`, scan/task/ledger/load/integration gates and exact source-to-destination reconciliation.
7. Prove every stock change is an authorized idempotent ledger movement with exact UOM/conversion/rounding, configured FIFO/FEFO/lot/batch/serial/expiry identity, reservation/custody linkage and no normal-role direct balance patch/delete.
8. Prove cycle count supports blind observations including zero, snapshot/concurrency control, governed recount/approval and exactly one reconciling adjustment movement.
9. Prove governed label/barcode template/version/identifier/print/reprint/void lineage, printer-job recovery and authorization after every scan; barcode possession must never grant access.
10. Prove warehouse billing events retain source/activity/contract/rate/UOM/currency/tax/rounding versions, hand off idempotent readiness to Finance and never mutate invoice, AR/AP, GL, settlement or cash truth.
11. Prove customer inventory access is read-only and intersects tenant, customer account, company/site, warehouse and owner scope across RLS/service, REST, GraphQL, lists/search/filters/aggregates/exports/jobs/caches/realtime; confirm full Portal remains Step 13.
12. Prove advanced claim/incident extends the Step 8 canonical case; evidence is private/scanned/source-linked; liability/reserve/recovery/closure decisions are human-governed; Finance handoff and operational reconciliation are exact.
13. Prove RPD-038 case-specific GPS/telematics adapters, signature/replay/rate-limit/failure controls and PostGIS geospatial correctness where applicable; reject a speculative universal provider abstraction or tenant fork.
14. Prove route/load planning is explainable decision support with constraints, alternatives and human commitment; no false optimum or autonomous operational/legal/financial decision.
15. Prove RPD-004 responsive online-first PWA behavior with no native/offline synchronization; RPD-032 scan-before-file access; RPD-033 REST/GraphQL parity; and complete accessible loading/empty/error/success/denied/conflict/degraded states.
16. Prove RPD-014 target-volume profiles and budgets for dispatch, task/scan, ledger, telemetry, jobs, billing and claims; use cursor pagination, selective queries, PostgreSQL durable jobs, bounded backpressure and limited scoped realtime with reconciliation under failure.
17. Prove tenant/customer/company/branch/warehouse/owner/record/field/file/job/realtime isolation; RLS/RBAC and service authorization must cover forged IDs, scans, exports, aggregates, callbacks and support/admin access.
18. Confirm RPD-022 explicitly allows Supreme Admin absolute CRUD. Verify normal-role protection, audit/warnings and recovery, but reject every tamper-proof, immutable-for-all or non-repudiation claim.
19. Prove RPD-025 retention/archival and recovery, RPD-035 support/observability/runbooks, clean install and Phase 4→5 upgrade, migration/type generation, backup/restore and no unreconciled ledger/event/job/Finance receipt.
20. Confirm full vendor/PO/compliance/rate lifecycle remains Step 11; employee/attendance/payroll remains Step 12; full Customer Portal remains Step 13; AI/predictive/enterprise depth remains Step 14. Phase 5 did not smuggle later-phase scope.
21. Confirm no production, external-pilot, partial-GA or market-ready claim. RPD-001/034/036 still require all major modules and complete validation before direct GA.
22. Confirm no unresolved critical/high tenant, customer, access, security, transport, inventory, financial, file, integration, schema, migration, performance or evidence blocker.

## Closure states

- `PHASE_5_VERIFIED`: every mandatory Advanced TMS/WMS runtime gate passes.
- `PHASE_5_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Phase 6 is blocked.
- `PHASE_5_BLOCKED`: a critical tenant/customer/access/security/transport/inventory/financial/file/integration/schema/contract/evidence gate fails.
- `PHASE_5_ROLLED_BACK`: the phase returned to a trusted checkpoint and must resume.

## Required output

Write artifact/task/capability/requirement checklist; checkpoint/schema/API/UI/access matrix; 24-capability × 24-anchor evidence map; transport and critical WMS E2E results; ledger/UOM/tracked-stock/cycle-count reconciliation; labels/scans; telemetry/geospatial/integration; billing/Finance and claim evidence; customer isolation/field/export/aggregate results; performance/job/realtime/failure recovery; security/files/audit/retention; migration/build/accessibility/observability results; later-phase boundary audit; RPD-022 and provider/legal residual-risk disclosure; residual issues; closure state/rationale; Phase 6 eligibility; and exact resume/next prompt.

## Completion gate

Set `PHASE_5_VERIFIED` only if every mandatory runtime check passes. This is not production, market, pilot or GA status. For package generation, the exact next command after Step 10 validation is `LANJUT STEP 11`.
