# Prompt 241 — Warehouse Billing Events

**Prompt ID:** `CG-S10-ATW-022`  
**Package document:** `CG-AABPP-ATW-241`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-241.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-022` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Commercial Operations; Epic: Billable Activity; Capability: Warehouse Billing Event Calculation and Finance Handoff; Feature slice: event capture, contract/rate reference, quantity/UOM, calculation, approval/readiness, handoff and reconciliation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement source-linked warehouse billing events and a compatible Finance handoff without creating invoices, receivables, payables or journals in WMS.

## 5. Business value

Convert verified warehouse activity into accurate, explainable billable evidence while retaining Finance ownership of accounting.

## 6. Source requirement

OPS-WMS-001..004 billing slice, OPS-CST-001..004 advanced slice and verified Finance contracts. Cite exact source sections, runtime evidence, rate/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schemas/migrations/contracts/routes/modules, Finance handoff versions, package manager/scripts, environment, baseline and trusted checkpoint.

## 8. Preconditions

Read all persistent ledgers/build logs, source requirements and verified Phase 4 Finance contracts. Inspect warehouse events, customer contracts/rates, Finance readiness APIs/jobs and tests; run baselines, state plan/files, and stop on inventory/financial/tenant/phase-boundary conflict.

## 9. Upstream dependencies

ATW-231..240 and verified Phase 4 Finance billing/readiness handoff. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-242..248, Finance consumers and future Step 11 vendor contracts/Step 13 portal. Identify affected schemas/services/APIs/jobs/audit/reports/tests/docs.

## 11. Allowed files/folders

Use only exact Advanced WMS billing-event and approved Finance handoff schema, migration, service, UI, job, test and documentation paths. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Invoice, AR/AP, GL or settlement mutation; full procurement/vendor/portal implementation; duplicate Finance roots; tenant forks; applied-migration edits; destructive cleanup; permission/test weakening; unrelated user changes.

## 13. Database impact

Add billable activity/event, source warehouse task/event version, customer/contract/rate reference, event type, exact quantity/UOM, currency/tax inputs, calculated components, status/approval, idempotent Finance handoff and reconciliation outcome.

## 14. API impact

Shared REST/GraphQL preview/calculate/recalculate-with-version/review/approve/read/export and Finance readiness/handoff-status operations using one domain service, auth, field policy, idempotency, audit and optimistic versioning.

## 15. UI/UX impact

Billing-event queue/detail, source lineage, calculation explanation, exception/review and handoff state. Include loading, empty, error, success, denied, stale-rate and Finance-degraded states; responsive online-first PWA, accessible controls and no dead action.

## 16. Security impact

Customer contract/rate/amount fields use strict roles and field policy; warehouse users cannot post accounting; source IDs never bypass authorization. Preserve tenant/customer/company/branch/warehouse scope, RLS/RBAC, server-only secrets and private export/file controls.

## 17. Performance impact

Index tenant/customer/warehouse/event-type/status/source/date/contract; calculate and hand off bounded batches via durable jobs. Use cursor pagination, selective queries, backpressure and limited realtime; measure throughput/latency and avoid duplicate fan-out.

## 18. Audit impact

Record source event/version, customer, contract/rate/tax/currency/UOM versions, components/rounding, reviewer/approval, handoff attempts, Finance receipt ID and reconciliation. Include correlation/idempotency and before/after/event chain.

## 19. Data migration impact

Create events only from evidenced source activity; do not infer historic billability or mark invoices. Reconcile source totals and Finance receipts. Use additive/expand-contract migrations, never edit applied migrations, and rehearse rollback.

## 20. Detailed implementation tasks

- Inspect WMS activity and verified Finance handoff contracts.
- Define billable types: storage, receiving, handling, putaway, pick, pack, outbound and approved value-added work.
- Define exact quantity/UOM, contract/rate/tax/currency/version and rounding semantics.
- Implement calculation, review, durable idempotent handoff and reconciliation UX/jobs.
- Test retries, reversals/corrections, access, performance and compatibility.

## 21. Main flow

Verified warehouse activity emits one source-versioned billing event, service resolves the effective contract/rate and exact measure, authorized review marks it ready, and Finance accepts an idempotent billing-readiness handoff.

## 22. Alternative flow

Accrue storage by approved time basis, aggregate only where contract permits while retaining line lineage, place an event on commercial hold, or create a corrective event tied to the original.

## 23. Exception flow

Block missing/ambiguous contract, invalid rate/UOM/currency/tax, stale source, duplicate event, unexplained amount, unauthorized override, Finance rejection/timeout or reconciliation mismatch. Preserve evidence and safe retry/resume.

## 24. Business rules

- One source activity/version and billing rule yields at most one active billing event; retries are idempotent.
- Calculation stores exact measure, UOM/conversion, rate/config version, currency, rounding and explanation.
- WMS emits Finance readiness only; it never mutates invoice, AR/AP, GL or settlement truth.
- Corrections reference/reverse prior events; no silent amount rewrite after handoff.
- Extend canonical Phase 3/4 records and contracts; no duplicate truth or re-entry.
- RPD-022 prevents immutable/tamper-proof claims; no tenant fork, autonomous pricing, offline sync or partial-GA claim.

## 25. Validation rules

- Source activity is final/eligible and compatible with customer/warehouse/contract/effective date.
- Quantity/UOM/rate/currency/tax/rounding and calculation reconcile exactly.
- Reject tenant/customer/warehouse/source/config/version mismatch, stale mutation and duplicate active event.
- Every approval/handoff/correction is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Warehouse users view source facts; commercial roles review calculated events; designated approvers release readiness; Finance roles consume/reconcile. Enforce database/service field and record policy for list/search/export/realtime.

## 27. Test data requirement

Storage/receiving/putaway/pick/pack/outbound/value-added events; tiered/flat rates; UOM conversion; multi-currency/tax inputs; hold/correction; duplicate retry; Finance rejection and Tenant A/B customer fixtures.

## 28. Tests to create/update

- Source uniqueness, exact calculation/UOM/rate/rounding and correction tests.
- Finance contract/idempotency/retry/rejection/reconciliation tests.
- RLS/RBAC/field-policy, migration, target-volume and accessibility tests.
- Inbound→outbound E2E proving billable events without accounting mutation.

## 29. Regression tests

All warehouse flows/ledger, customer contract reads, Finance invoice/readiness/audit and future procurement/portal. Re-run isolation, financial compatibility, API/job/browser/accessibility and critical E2E suites.

## 30. Commands to run

Detect and run repository lint/typecheck/test/build plus database migration/type generation, finance-contract, reconciliation, security, target-volume billing-job and relevant E2E commands. Do not disable a gate.

## 31. Documentation to update

Billable type/source/calculation/rate/version/rounding/correction/Finance handoff contract and exception/reconciliation runbook. Update persistent ledgers, traceability, schema/API/data flow, build log and user/admin/Finance/support docs.

## 32. Rollback/recovery note

Stop new readiness handoffs, preserve accepted receipts, cancel only eligible unaccepted events and use governed corrective events for released amounts. Reconcile WMS events with Finance before resume; no destructive history edits.

## 33. Acceptance criteria

- Eligible WMS activities generate exact, explainable billing events once.
- Finance accepts a compatible idempotent handoff without WMS accounting mutation.
- Holds, failures and corrections are auditable/reconcilable.
- Mandatory gates pass at one checkpoint with source-to-evidence traceability.

## 34. Definition of Done

No placeholder/fake persistence/dead action; migrations, types, RLS/RBAC/field policy, shared APIs, UX, jobs, tests, docs, audit, performance evidence and rollback are complete; no critical financial/inventory/security blocker remains.

## 35. Completion report format

Report IDs/checkpoint; changed files/contracts; decisions/configs; commands/results; calculation/Finance, tenant/access, idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next task. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-242 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
