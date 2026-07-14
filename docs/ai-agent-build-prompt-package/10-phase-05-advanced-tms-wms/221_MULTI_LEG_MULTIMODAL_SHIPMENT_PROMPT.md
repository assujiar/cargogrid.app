# Prompt 221 — Multi-Leg and Multimodal Shipment

**Prompt ID:** `CG-S10-ATW-002`  
**Package document:** `CG-AABPP-ATW-221`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-221.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-002` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Advanced Transportation; Epic: Shipment Network Execution; Capability: Multi-Leg and Multimodal Shipment; Feature slice: canonical shipment root, ordered legs/stops, mode handoff, cargo allocation and lifecycle aggregation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Extend the verified Shipment Order into ordered multi-pickup, transfer, linehaul and delivery legs across land, air and sea without duplicating the canonical root.

## 5. Business value

Support real freight-forwarding networks while preserving one source of truth from quote/job through Finance.

## 6. Source requirement

OPS-SHP-001..004 and OPS-TMS-001..004 advanced Phase 5 slices; CPD-018/019. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-220; verified Phase 3 Job Order/Shipment Order/lifecycle/milestone/ePOD/cost/readiness and Phase 4 Finance contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-222..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add/extend ordered shipment leg, stop/handoff, mode/service, schedule, party/location, cargo allocation, custody, canonical leg state and aggregate shipment-state references with tenant-aware constraints.

## 14. API impact

Shared REST/GraphQL plan, validate, create/amend-draft, confirm, read network/timeline and compatibility operations over the existing Shipment service. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Shipment detail gains leg/stop timeline, map/list, custody handoff, cargo allocation, aggregate status, exceptions and complete responsive states without replacing the Phase 3 screen. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Preserve tenant/company/customer/record/field scopes across every leg and handoff; prevent IDOR via nested leg IDs and restrict sensitive vendor/cost fields. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Index tenant/shipment/sequence/status/mode/location/time; load bounded leg windows and avoid N+1 party/cargo/milestone fetches. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record root/leg/source versions, sequence/allocation changes, handoff actors/times, status aggregation, overrides and compatibility impact. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

Evolve existing single-leg shipments into one explicit legacy-compatible leg with reversible mapping and reconciliation to milestones/cost/billing evidence. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Inventory Phase 3 shipment schema/contracts/consumers and legacy single-leg semantics.
- Define root-leg-stop-handoff allocation and canonical state aggregation invariants.
- Implement additive schema, service, REST/GraphQL and leg-aware UX.
- Migrate single-leg data and preserve cost/readiness/Finance compatibility.
- Run lineage, lifecycle, isolation, migration, performance and E2E evidence.

## 21. Main flow

Planner opens a verified shipment, builds ordered compatible legs/stops with allocated cargo and handoffs, validates the network, confirms it, and each leg executes while aggregate state derives deterministically.

## 22. Alternative flow

Split cargo across compatible legs, add an approved transshipment, revise only unstarted legs or cancel/replan a downstream leg with impact preview.

## 23. Exception flow

Block sequence gaps/cycles, cargo over-allocation, incompatible mode/service/location, broken custody, started-leg destructive edit, stale version, duplicate leg event or Finance/source lineage break. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Shipment Order remains the canonical root; a leg cannot become an independent duplicate shipment.
- Allocated quantity across active legs never exceeds source cargo and each handoff preserves custody lineage.
- Aggregate shipment state is derived from canonical leg states under a versioned rule.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Leg order, stops, mode/service, parties, cargo, schedule and handoff compatibility are complete.
- Started/completed leg fields obey immutable-for-normal-workflow boundaries and governed correction.
- Existing API/webhook/export consumers receive compatible versioned contracts.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Transport planners create/amend; dispatch executes authorized legs; Operations/Finance view scoped lineage; customer-facing projections expose only assigned shipment/customer data. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Single-leg migrated, multi-pick/drop, land-air-sea transfer, split cargo, sequence cycle, partial completion, failed handoff, concurrent edit and Tenant A/B fixtures. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Root/leg/stop/allocation/state/custody database and service tests.
- REST/GraphQL compatibility, migration, milestone/cost/billing-readiness/Finance integration tests.
- RLS/RBAC/customer isolation, concurrency/idempotency, performance, accessibility and critical E2E tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

Phase 3 Job/Shipment/lifecycle/assignment/milestone/ePOD/cost/readiness and Phase 4 invoice/AP/profitability contracts. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Canonical shipment/leg/handoff data dictionary, lifecycle aggregation, migration/compatibility and replan recovery runbook. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable advanced creation, preserve migrated compatibility view, reverse only unstarted additive leg changes and reconcile root/events/cost/readiness before resume. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Legacy and new shipments share one canonical root.
- Multi-leg cargo, custody and state reconcile exactly.
- Phase 3/4 consumers remain compatible and no data is re-entered.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-222 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

