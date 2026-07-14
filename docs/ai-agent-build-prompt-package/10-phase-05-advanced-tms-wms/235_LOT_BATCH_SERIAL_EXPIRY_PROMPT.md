# Prompt 235 — Lot, Batch, Serial and Expiry

**Prompt ID:** `CG-S10-ATW-016`  
**Package document:** `CG-AABPP-ATW-235`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-235.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-016` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Inventory Control; Epic: Controlled Stock Identity; Capability: Lot, Batch, Serial and Expiry Control; Feature slice: item policy, capture, uniqueness, status, FIFO/FEFO allocation, hold/expiry and traceability; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement configurable lot/batch/serial/expiry dimensions and allocation rules only where item/customer policy requires them.

## 5. Business value

Enable regulated and traceable stock handling without forcing irrelevant controls on every SKU.

## 6. Source requirement

OPS-WMS-001..004 controlled-stock slice; canonical SKU/inventory fields. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-232..234. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-236..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add item/owner control policy version, lot/batch identity, serial uniqueness, manufacture/expiry dates, status/hold, genealogy references where supported and indexes integrated with ledger dimensions.

## 14. API impact

Shared REST/GraphQL policy/identity validate, capture, read trace, availability/allocation candidate and hold/release operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Receiving/inventory/picking controls conditionally request and scan required dimensions, show expiry/hold warnings, trace history and provide authorized manual fallback. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Owner/customer and sensitive item data scoped; barcode/serial enumeration resistance where exposed; files/certificates private/scanned/signed. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index owner/item/lot/batch/serial/expiry/status/location; batch availability and FEFO/FIFO queries without N+1. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record policy/version, captured identity/dates/status, scan/manual override, hold/release, allocation decision and movement trace. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Enable controls only after existing stock is mapped/reconciled; unknown lot/serial/expiry remains explicitly blocked/held per policy. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory item/customer traceability requirements and existing identifiers.
- Define versioned control policy, uniqueness/status and FIFO/FEFO semantics.
- Implement schema/validation/APIs and conditional scan UX.
- Integrate ledger, receiving, picking, count/adjustment and trace queries.
- Test controlled/uncontrolled items, expiry, uniqueness, migration and access.

## 21. Main flow

Published item/owner policy requires relevant identifiers at receipt, ledger preserves them, availability excludes held/expired stock and picking suggests FIFO/FEFO candidates with human-confirmed scans.

## 22. Alternative flow

Handle uncontrolled item, approved unknown lot under hold, manual serial entry with reason or policy-version transition after reconciliation.

## 23. Exception flow

Block missing required control, duplicate serial, invalid expiry/manufacture order, expired/held allocation, owner/item mismatch, policy change with unmapped stock or unauthorized release. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Controls are conditional and versioned; absent relevance never justifies fabricated data.
- Serial is unique in governed scope and quantity semantics are explicit.
- FIFO/FEFO is a candidate rule; actual allocation remains server-validated and audited.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Policy version matches owner/item/effective time.
- Required identifiers/date/status and uniqueness are valid.
- Movement/pick/control dimensions remain identical through trace chain.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Warehouse users capture under task scope; supervisors hold/release/override; customers see only their owner-scoped permitted trace data. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Controlled/uncontrolled items, lot/batch, unique/duplicate serial, expired/near-expiry, FIFO/FEFO ties, unknown held stock, policy migration and cross-owner attempts. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Policy/required/serial/date/status/FIFO/FEFO and trace-chain tests.
- Receiving/ledger/picking/count/API/file integration tests.
- RLS/RBAC/customer-owner/enumeration isolation, migration, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Item master, receiving, ledger, picking, labels, claims, customer inventory and billing. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Control policy/identity/status/FIFO/FEFO/trace data dictionary and unknown/duplicate/expiry recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable only unused new policy, hold affected stock, restore prior allocation rule and reconcile ledger dimensions before resume. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Controlled stock is fully traceable.
- Expired/held or duplicate-serial stock cannot be allocated silently.
- Uncontrolled items avoid unnecessary fields.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-236 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

