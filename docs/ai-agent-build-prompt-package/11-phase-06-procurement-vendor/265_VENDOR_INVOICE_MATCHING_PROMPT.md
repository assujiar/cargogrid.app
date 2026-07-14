# Prompt 265 — Vendor Invoice Matching

**Prompt ID:** `CG-S11-PRC-016`  
**Package document:** `CG-AABPP-PRC-265`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-265.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-016` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement and Finance; Epic: Payables Control; Capability: Vendor Bill to PO Service Receipt Rate and Actual-Cost Matching; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Extend the canonical Phase 4 vendor bill with configurable exact matching, variance, dispute and approval evidence without duplicating AP or posting.

## 5. Business value

Prevent duplicate or inaccurate vendor charges while accelerating clean AP processing.

## 6. Source requirement

PRC-POI-001..004, BR-VIM-001, FINTEST-016 and verified FIN-AP contracts. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..264; verified Phase 4 vendor bill/AP and Phase 3/5 shipment/actual-cost/ePOD evidence. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-266..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add match case/version referencing canonical vendor bill, PO/contract, shipment/leg/service receipt/ePOD, actual cost, rate/tax/payment-term snapshots, quantity/UOM, amount/currency/rounding, line-level results, tolerance config, duplicate fingerprint, variance/dispute, approval and Finance readiness/reconciliation.

## 14. API impact

Shared REST/GraphQL create/evaluate/re-evaluate-with-version, line-map, accept-within-policy, dispute, resolve, approve-exception, readiness and reconciliation-status operations; vendor bill/AP mutations remain Finance-owned. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Matching queue/detail with source documents, line mapping, exact variance explanation, tolerance, duplicates, missing evidence, dispute/response, approval and Finance handoff state. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Vendor bill, bank/tax, costs and documents are Finance-sensitive; strict field/separation policy, private scanned files, no vendor access to internal cost/margin or other invoices. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor/bill/PO/shipment/status/date/fingerprint; bounded line matching, async batch jobs, cursor queues, backpressure and target-volume reconciliation. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record vendor-bill/source versions, match rule/tolerance, quantity/UOM/rate/tax/currency/rounding, line results, duplicate fingerprint, variance/dispute/approval, handoff receipt and reconciliation. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Adopt existing Phase 4 bills and evidenced match links only; do not create duplicate bills/AP or infer a clean match; reconcile every migrated match to Finance. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Reconcile canonical Finance vendor-bill/AP ownership and match interface.
- Define two-/three-/multi-source line matching, tolerance, duplicate and partial invariants.
- Implement exact engine, queue/detail, dispute/approval and durable batch jobs.
- Emit idempotent source-linked match readiness/result to Finance only.
- Run FINTEST-016, quantity/value/tax, duplicate, concurrency, isolation and reconciliation tests.

## 21. Main flow

A canonical Finance vendor bill opens a match case, service maps lines to PO/contract and shipment/service/ePOD/actual-cost/rate evidence, calculates exact variances, clears within approved policy or routes dispute/exception approval, then hands result to Finance.

## 22. Alternative flow

Non-PO match under an explicit policy, partial invoice/fulfillment, consolidated invoice across shipments, credit/correction linked to original or approved tolerance exception.

## 23. Exception flow

Block duplicate invoice/fingerprint, wrong vendor/tenant, missing PO/service evidence, quantity/value/tax/UOM/currency mismatch, over-tolerance, stale source, locked Finance state or ambiguous retry. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Finance owns canonical vendor bill, AP, posting, period lock, reversal, settlement and reconciliation; Procurement owns match evidence/exception workflow.
- Configured two-, three- or multi-source match must retain every source/version and exact line equation.
- Within-tolerance auto-clear may be configured only after human-approved policy; over-tolerance requires dispute/approval.
- No match result posts a journal or executes payment; retries cannot duplicate bill, case or Finance receipt.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate vendor/legal identity, bill uniqueness, PO/contract/source compatibility, received/service quantity/UOM, rate/tax/payment term/currency/rounding, tolerance and current Finance state/version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement matches/disputes; designated approvers accept exceptions; Finance owns bill/AP/posting; vendor may respond to own dispute with allowed fields/files only. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Exact match, price/qty/tax/UOM variance, partial/consolidated/non-PO policy, duplicate invoice, missing ePOD, dispute/correction, retry and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Line equation/quantity/UOM/rate/tax/currency/rounding/tolerance tests.
- Duplicate fingerprint/partial/consolidated/dispute/approval/idempotency tests.
- RLS/RBAC/field/file/vendor/Finance separation tests.
- FINTEST-016 and bill→match→AP-readiness→reconciliation E2E/load tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Phase 4 vendor bill/AP/posting/period/settlement, PO/contracts, shipment/ePOD/actual cost/rates and vendor performance invoice accuracy. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Canonical vendor-bill match-source/line/equation/tolerance/duplicate/dispute/Finance handoff contract and mismatch/retry/reconciliation runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Stop new evaluations/handoffs, preserve Finance bills/accepted receipts, revert only pending match calculations and reconcile AP/source evidence before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Canonical vendor bills match exact source evidence without duplicate AP truth.
- Variance, tolerance, duplicate, dispute and approval are explainable.
- Finance-only posting/payment boundary is enforced.
- FINTEST-016 and reconciliation/isolation gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-266 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

