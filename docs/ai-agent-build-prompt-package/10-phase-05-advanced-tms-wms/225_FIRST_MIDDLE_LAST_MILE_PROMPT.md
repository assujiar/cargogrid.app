# Prompt 225 — First-, Middle- and Last-Mile Orchestration

**Prompt ID:** `CG-S10-ATW-006`  
**Package document:** `CG-AABPP-ATW-225`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-225.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-006` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Advanced Transportation; Epic: End-to-End Mile Execution; Capability: First-, Middle- and Last-Mile Orchestration; Feature slice: mile classification, pickup/consolidation/linehaul/deconsolidation/delivery dependencies, handoff and SLA; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement configurable first-, middle- and last-mile orchestration over canonical legs, stops, handoffs and milestones.

## 5. Business value

Coordinate end-to-end logistics stages with clear ownership, dependency and customer-visible progress.

## 6. Source requirement

OPS-SHP/TMS/TRK-001..004 advanced mile slice. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-221 and ATW-224; verified Phase 3 milestones/exceptions. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-226..228, ATW-243..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add mile classification and dependency/handoff metadata to canonical legs/stops, stage readiness/checklist, SLA version and aggregate progress without separate duplicate shipment roots.

## 14. API impact

Shared REST/GraphQL stage plan/read, readiness, handoff-confirm, exception and progress projection operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Operations control-tower stage timeline with mile owner, readiness, SLA, handoff, exception and customer-safe aggregate progress. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Handoff parties/locations/documents obey tenant/customer/record/field scope; public/customer projections never expose internal route/resource/cost details. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index shipment/mile/status/time/owner; derive aggregate progress with batched events and selective active updates. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record stage classification/rule version, readiness, custody handoff, actor/time/location/evidence, SLA and override/exception. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Classify existing compatible legs only through explicit rule/mapping; leave uncertain histories unclassified with owner. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory leg/milestone/handoff and customer projection contracts.
- Define canonical mile stages, dependencies, readiness and SLA semantics.
- Implement shared services/APIs and control-tower timeline.
- Integrate planning/dispatch/telemetry/exceptions and customer-safe progress.
- Test handoff, dependency, scope, migration and E2E.

## 21. Main flow

Confirmed shipment stages execute in dependency order from pickup through consolidation/linehaul/deconsolidation to delivery, with server-validated readiness and custody handoffs.

## 22. Alternative flow

Skip or combine a stage under an approved service template, reassign an unstarted stage, or manage partial split cargo with explicit dependency.

## 23. Exception flow

Block handoff before readiness, broken custody, stage cycle, stale plan, incompatible location/mode, SLA miscalculation, unauthorized customer projection or silent partial completion. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Mile labels configure canonical stage semantics; tenant wording cannot break reporting.
- Stage completion requires its mandatory leg/milestone/handoff evidence.
- Customer progress is derived and scope-safe, not a second editable lifecycle.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Stage/leg order and dependencies are acyclic and complete.
- Readiness, custody, SLA and evidence rules resolve from published versions.
- Aggregate progress reconciles to underlying legs and milestones.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Operations manages internal stages; assigned field/dispatch users confirm scoped tasks; customers receive only allowed progress projection. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Pickup-linehaul-delivery, consolidation/deconsolidation, skipped/combined stage, split cargo, failed handoff, SLA breach, multiple customers and cross-tenant attempts. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Stage/dependency/readiness/SLA/aggregate-progress tests.
- Leg/planning/dispatch/milestone/customer-projection REST/GraphQL E2E tests.
- RLS/RBAC/customer isolation, idempotency/concurrency, performance and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Phase 3 shipment/tracking/ePOD/readiness, advanced leg/planning and future Customer Portal contracts. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Mile-stage/data-flow/handoff/SLA specification and broken-handoff/replan recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Revert only unstarted stage metadata, restore prior canonical leg plan and reconcile progress/custody/events before resume. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Stage dependencies and custody are deterministic.
- Customer-safe progress matches canonical execution.
- No second shipment lifecycle or data re-entry is introduced.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-226 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

