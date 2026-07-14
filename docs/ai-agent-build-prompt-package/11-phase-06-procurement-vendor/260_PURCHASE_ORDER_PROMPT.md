# Prompt 260 — Purchase Order

**Prompt ID:** `CG-S11-PRC-011`  
**Package document:** `CG-AABPP-PRC-260`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-260.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-011` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement Execution; Epic: Commercial Commitment; Capability: Purchase Order Creation, Approval, Amendment and Fulfillment; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement exact source-linked purchase orders as governed vendor commitments without posting accounting or duplicating shipment execution.

## 5. Business value

Control vendor scope, quantities, prices, terms and approvals before fulfillment and invoice matching.

## 6. Source requirement

PRC-POI-001..004 with PRC-SRC/RTE and FIN-AP dependencies. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..259; verified Finance currency/tax/payment-term and Operations demand contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-261..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add PO root/version/number, vendor/company/branch, sourcing/RFQ/comparison/quote/rate/contract sources, service/item lines, quantity/UOM, price/components/currency/tax/rounding, delivery/service period, terms, approvals, commitment, amendments/cancellation, fulfillment and match references.

## 14. API impact

Shared REST/GraphQL draft-from-selection, validate/calculate, submit/approve, issue/acknowledge, amend, cancel-eligible, close and fulfillment/match read operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

PO queue/editor/detail with inherited source lines, exact totals, terms/documents, approval/version timeline, vendor acknowledgement, amendment diff and fulfillment/match status. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Restrict cost/tax/bank/terms by field; issue only to the selected vendor through scoped channels; private scanned documents/signed URLs; no customer exposure. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/company/branch/vendor/status/date/source/number; cursor queues, selective lines, async PDF/issue/export and target-volume bulk generation. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source versions, lines/UOM, rate/components/currency/tax/rounding, approval, issued document/version, acknowledgement, amendments, cancellation, fulfillment and match lineage. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Link existing commitments only with evidenced source/vendor/value/status; do not infer approval/acknowledgement/fulfillment or create AP. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define PO identity/lifecycle/source/line/total/commitment invariants.
- Implement source mapping and exact calculation using approved quote/rate/terms.
- Implement schema/policies/services/APIs/editor/document/issue/acknowledgement.
- Implement governed amendment/cancellation/fulfillment and match linkage.
- Test exact totals, versions, approvals, vendor scope, migration and Finance boundary.

## 21. Main flow

Approved vendor selection creates a draft PO without re-entry, Procurement validates lines/terms/totals, submits for approval, issues the approved version, captures acknowledgement and tracks fulfillment for matching.

## 22. Alternative flow

Blanket/call-off where configured, partial fulfillment, schedule line, vendor-requested revision before approval, or governed amendment/cancellation after issue.

## 23. Exception flow

Block unapproved/ineligible vendor, stale selection/rate, invalid UOM/currency/tax/term, over-budget/authority, duplicate issue, missing acknowledgement or amendment against matched/closed quantity. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- PO snapshots selected vendor, demand, quotation/rate/contract/config and exact commercial calculation.
- Approved/issued PO is changed only by linked amendment/version; no silent overwrite.
- PO commitment does not create AP, journal, settlement or cash movement.
- Fulfillment references canonical shipment/service evidence; PO does not duplicate Operations execution.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate vendor eligibility, source approval/version, line quantity/UOM/service/period, price/components/currency/tax/rounding, authority/budget if configured and lifecycle/version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement drafts/issues/amends; approvers authorize; vendor sees/acknowledges own issued PO; Operations/Finance view only necessary source/fulfillment/match fields. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Single/multi-line, service/quantity PO, partial fulfillment, amendment/cancel, blanket/call-off config, stale rate, duplicate issue, vendor reject and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- PO identity/number/lifecycle/source/idempotency tests.
- Exact line/component/currency/tax/rounding/total tests.
- Approval/amendment/cancellation/acknowledgement/concurrency tests.
- RLS/vendor scope, Operations fulfillment and Finance no-posting/match contract E2Es.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Sourcing/comparison/approval, rate engine, Operations shipment/actual cost, Finance vendor bill/AP and documents. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

PO source/line/calculation/lifecycle/issue/acknowledgement/amendment/fulfillment/match contract and dispute/cancel/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Stop issue jobs, cancel only eligible uncommitted drafts, preserve issued/amended history and reconcile vendor/fulfillment/match consumers before restore. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- POs inherit approved selection and calculate exactly.
- Approval, issue, acknowledgement and amendments preserve versions.
- Operations fulfillment and Finance boundaries remain intact.
- Vendor isolation and invoice-match readiness pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-261 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

