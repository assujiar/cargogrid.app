# Prompt 228 — Advanced Milestone and Exception

**Prompt ID:** `CG-S10-ATW-009`  
**Package document:** `CG-AABPP-ATW-228`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-228.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-009` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Operations Control Tower; Epic: Predictable Network Execution; Capability: Advanced Milestone and Exception Management; Feature slice: leg/stage templates, ETA/ETD, dependencies, telemetry signals, SLA, root cause, recovery and customer-safe projection; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Extend Phase 3 milestones/exceptions across legs and mile stages with dependency-aware ETA/ETD, telemetry signals, SLA escalation and recovery plans.

## 5. Business value

Give the control tower early, explainable visibility into network delays and actionable recovery.

## 6. Source requirement

OPS-TRK-001..004 advanced slice; OPS-DOC incident linkage. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-221, ATW-225..227 and verified Phase 3 milestone/exception contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-243..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Extend milestone template/instance with leg/stage/dependency, planned/estimated/actual time, source confidence/version; exception root cause/impact/recovery/SLA/owner/escalation and customer-safe projection.

## 14. API impact

Shared REST/GraphQL template/instance/read, event ingest, acknowledge/assign/escalate/recover/close and timeline projection operations. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Control-tower timeline/map/exception queue with dependency impact, ETA confidence/source, owner/SLA, recovery plan and customer-visibility preview. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Internal cause/cost/vendor/driver data is field-restricted; customer projection is allowlisted; telemetry cannot authorize state change alone. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index active leg/stage/status/SLA/time; selectively update active scope, batch dependency impact and bound ETA computations. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record template/rule/source versions, event/received time, ETA changes, exception detection/manual action, escalation, recovery, customer visibility and override. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Map Phase 3 milestones/exceptions additively to root or leg/stage with explicit unresolved classification. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory Phase 3 timeline/exception and advanced source signals.
- Define leg/stage dependency, ETA/source confidence and recovery semantics.
- Implement extensions, shared services/APIs and control-tower UX.
- Integrate telemetry/dispatch/capacity/claim/customer projections.
- Run order/dependency/SLA/access/migration/load E2E tests.

## 21. Main flow

Canonical/manual/telemetry event updates an authorized leg milestone, dependency engine recalculates impacted ETA, opens/escalates exception if rule triggers, owner executes recovery and customer sees only approved projection.

## 22. Alternative flow

Manually confirm an uncertain signal, suppress duplicate alert with reason, revise recovery plan or rebaseline unstarted milestones under approval.

## 23. Exception flow

Block contradictory terminal event, invalid dependency cycle, stale/low-confidence autonomous state mutation, duplicate escalation, SLA calendar error, unauthorized customer exposure or silent closure. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Event time and received time are separate; source/confidence remains visible.
- Derived ETA/exception is explainable and cannot silently replace confirmed actual events.
- Exception closes only with required recovery/evidence and downstream impact resolution.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Milestone dependency graph is acyclic and templates are compatible with leg/stage/service.
- State/event/order/idempotency and ETA inputs are valid.
- Customer visibility classification is explicit per field/event.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Control tower manages internal exceptions; assigned operators update scoped actions; managers approve rebaseline/override; customers receive only allowlisted status. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Multi-leg delays, missed handoff, telemetry late/duplicate, ETA changes, dependency cascade, SLA breach, recovery/rebaseline, customer restrictions and Tenant A/B. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Dependency/event-order/ETA/source-confidence/SLA/escalation/recovery tests.
- Leg/dispatch/telemetry/capacity/claim/customer projection API E2E tests.
- RLS/RBAC/field/customer isolation, idempotency/concurrency, load/realtime and accessibility tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Phase 3 milestone/exception/tracking/ePOD/readiness, notifications, Finance impacts and future portal. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Advanced milestone/dependency/ETA/exception/recovery contract and conflicting-signal/SLA/outage runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable faulty derived rule, restore last trusted confirmed events, recompute affected projections and reopen unresolved exceptions before resume. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Advanced timeline reconciles to canonical leg/stage events.
- Exceptions are actionable and SLA-controlled.
- Customer projection never leaks restricted causes or resources.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-229 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

