# Prompt 223 — Fleet and Driver

**Prompt ID:** `CG-S10-ATW-004`  
**Package document:** `CG-AABPP-ATW-223`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-223.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-004` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Transport Resources; Epic: Operational Resource Control; Capability: Fleet, Vehicle and Driver Operational Baseline; Feature slice: resource identity reference, capacity, availability, document/status and assignment eligibility; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement operational fleet/vehicle/driver resources and eligibility needed for dispatch while preserving Procurement vendor and HR employee ownership boundaries.

## 5. Business value

Give planners trustworthy capacity and availability without creating duplicate vendor or employee masters.

## 6. Source requirement

OPS-TMS-001..004 fleet/driver slice; UX master data; Step 11/12 boundary. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-221..222; Platform master/config; verified Phase 3 resource assignment. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-224..228, ATW-243..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add/extend operational fleet category, vehicle/resource, driver operational profile/reference, capacity dimensions, service/branch coverage, availability/status and document-expiry eligibility with canonical vendor/employee references where available.

## 14. API impact

Shared REST/GraphQL resource list/read, draft maintain, activate/deactivate, availability, eligibility and assignment-impact operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Operations resource catalogue/calendar/detail with capacity, branch/service, status/document expiry, availability, assignments and clear vendor/HR ownership links. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Driver personal data is minimized/field-protected; vendor banking/tax and HR/payroll are excluded; document files private/scanned/signed; assignment uses server scope. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/branch/type/status/availability/service/date; query eligibility in batches and avoid per-resource schedule calls. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record resource/reference/capacity/status/document/availability changes, assignment eligibility decision, actor/source and override. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Adopt existing Phase 3 assignment identities and map vendor/employee references explicitly; ambiguous duplicates remain blocked. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory Phase 3 resources and future Procurement/HR ownership contracts.
- Define operational resource identity, capacity, availability and eligibility boundaries.
- Implement additive schema/services/APIs and resource UX.
- Integrate dispatch/planning/capacity and expiry/hold handling.
- Test duplicate identity, privacy, eligibility, concurrency and handoffs.

## 21. Main flow

Authorized Ops Admin creates or links an operational resource, validates capacity/coverage/status/documents, activates it, and dispatch eligibility resolves against current availability.

## 22. Alternative flow

Use an external vendor resource reference, temporarily hold a vehicle/driver, schedule future availability or map a later Procurement/HR canonical identity.

## 23. Exception flow

Block duplicate physical identity, expired/invalid document, incompatible capacity/service/branch, concurrent assignment, inactive reference, unauthorized personal data or attempted vendor/HR source duplication. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Operational resource is not a substitute vendor or employee master.
- Eligibility derives from current status, capacity, coverage, documents and assignment window.
- Driver personal data is limited to operational necessity and retention/access policy.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Identifier/reference, capacity/UOM, service/branch, status, documents and availability are consistent.
- No overlapping incompatible assignment exists at commit.
- Deactivation/merge impact on active trips is reviewed and governed.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Ops Admin maintains operational fields; dispatcher reads eligible projections; Procurement/HR later own their domain fields; customer users see no driver-sensitive data. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Owned/leased/vendor fleet, internal/vendor driver references, expired docs, holds, multiple branches/services, concurrent assignments and cross-tenant actors. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Identity/capacity/availability/expiry/eligibility and overlap tests.
- Dispatch/planning REST/GraphQL and Procurement/HR contract integration tests.
- RLS/RBAC/field/PII/file isolation, migration, concurrency, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Phase 3 assignment, dispatch board, notifications/files, future Step 11 vendor and Step 12 HR contracts. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Resource ownership/data dictionary, eligibility/capacity/availability rules and duplicate/expiry/hold runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Deactivate only unused new resource paths, restore Phase 3 assignment compatibility and reconcile active assignment/reference mappings. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Dispatch receives one trustworthy eligible resource projection.
- No vendor/employee source is duplicated.
- Sensitive driver and document data stays protected.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-224 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

