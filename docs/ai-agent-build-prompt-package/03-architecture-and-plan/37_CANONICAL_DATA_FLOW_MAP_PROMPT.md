# Prompt 37 — Canonical Data Flow Map

**Prompt ID:** `CG-S3-ARCH-002`  
**Package document:** `CG-AABPP-ARCH-037`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/02_CANONICAL_DATA_FLOW_MAP.md`

## Objective and value

Define end-to-end canonical data movement, ownership, transformation, access, audit, and reconciliation across CargoGrid business lifecycles.

## Preconditions

Prompt 36 is complete at the verified discovery checkpoint. Read source lifecycles, data dictionaries, access design, API/integration architecture, finance rules, and Step 2 schema/route/security evidence.

## Required tasks

1. Map lead → account/opportunity → costing → quotation/contract → booking/shipment → TMS/WMS execution → milestone/ePOD → billing readiness → invoice/receipt/vendor bill/payment → GL/profitability.
2. Map vendor onboarding/rate/sourcing/PO/matching, HRIS/payroll, three-channel ticketing, Customer Portal, and loyalty earning/redemption/liability flows.
3. For each step record system of record, canonical entity/ID, tenant context, input/output contract, validation, transformation, status transition, event/job, audit, access layer, retention, and reconciliation.
4. Cover import/export, files and malware scan/quarantine, notifications/webhooks, reporting/live dashboard reads, scheduled jobs, retry/DLQ/idempotency, and integration failure/replay.
5. Identify duplicate entry, ambiguous ownership, non-atomic handoffs, stale snapshots, orphan records, cross-tenant risks, missing lineage, and finance discontinuities.
6. Separate operational truth from read models, cached views, exports, analytics, and external representations.
7. Model main, alternative, exception, reversal/cancellation, retry, and recovery paths for critical flows.
8. Provide diagrams plus exact flow tables and reconciliation checkpoints.

## Required output

Include checkpoint, canonical entity register, lifecycle flow maps, lineage table, integration/event/job flows, file flow, read-model/report flow, reconciliation points, exception/recovery paths, data classifications, retention/legal-hold implications, gaps, ADR candidates, and downstream schema/API/test inputs.

## Completion gate

Complete only when every critical E2E/UAT flow has traceable ownership from origin to final record, tenant/access context is explicit, financial flows reconcile, and unknown current-state facts are blocked rather than invented.
