# Prompt 226 — GPS and Telematics Integration

**Prompt ID:** `CG-S10-ATW-007`  
**Package document:** `CG-AABPP-ATW-226`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-226.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-007` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Transportation Integration; Epic: Trusted Movement Events; Capability: Case-Specific GPS and Telematics Integration; Feature slice: provider-specific adapter, canonical location event, signature/auth, order/replay, geofence and retention; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement an explicitly scoped GPS/telematics adapter that normalizes trusted movement events into canonical shipment/leg tracking without creating a universal provider abstraction.

## 5. Business value

Improve active shipment visibility and exception detection while controlling integration, privacy and scale risk.

## 6. Source requirement

OPS-TMS/TRK-001..004 integration slice; RPD-015/025/033/038. Cite exact source sections, runtime evidence, ADR/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and source requirements. Inspect repository/schema/API/UI/jobs/integrations/tests, detect package manager, run feasible baseline gates, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-221, ATW-225 and one approved provider/contract; Platform API/webhook/job/PostGIS controls. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-228, ATW-243..248. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Finance/portal contracts, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced TMS/WMS schema, migration, service, UI, integration/job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate Phase 3 roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add case-specific device/resource mapping, inbound event source/id/time/received time/position/accuracy/speed/heading, signature/auth result, dedup/order status, canonical tracking link and retention partition/index strategy.

## 14. API impact

Provider-specific webhook/poll adapter plus shared canonical REST/GraphQL tracking read contract; validate signature/auth, replay window, rate and schema. REST and GraphQL share one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Integration admin status/mapping/error/replay view and Operations map/timeline showing source freshness/accuracy without exposing credentials or raw private payload. Include loading, empty, error, success, permission-denied and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Server-only credentials, signature/auth/replay validation, rate limiting, device/resource/tenant mapping, location minimization/retention and restricted driver/customer access. Preserve tenant/customer isolation, RLS, RBAC, company/branch/warehouse/owner scope, field/record policy, server-only secrets, file controls and RPD-022 risk disclosure.

## 17. Performance impact

Ingest asynchronously through PostgreSQL durable jobs, deduplicate early, partition/index after measured need, batch-map/geofence and limit realtime to active authorized shipments. Use selective columns, server filter/sort/search/cursor pagination, query budgets, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record provider/config/schema version, request hash/auth result, event/received/order/dedup, mapping, canonical outcome, error/retry/DLQ and privileged replay. Include correlation/idempotency key, actor/context, source/config versions, before/after or movement/event chain, outcome and privileged evidence.

## 19. Data migration impact

No raw history import without explicit scope, retention, mapping, dedup and load rehearsal. Use additive or expand-and-contract migrations; never edit an applied migration. Inventory/operational history changes require backup, rehearsal and reconciliation.

## 20. Detailed implementation tasks

- Confirm provider contract, payload/auth/rate/retention and failure semantics.
- Define case-specific adapter and canonical event/mapping/order contract.
- Implement secure ingestion/job/dedup/mapping/geofence and read projections.
- Integrate milestones/exceptions/map freshness and operational controls.
- Run replay/order/privacy/load/failure/compatibility tests.

## 21. Main flow

Provider sends authenticated event, adapter validates/deduplicates/maps it, job orders it using event/received time, stores governed evidence and updates authorized canonical tracking/geofence signals.

## 22. Alternative flow

Use approved polling, manual device mapping, quarantine unknown events or replay a bounded failed batch after root-cause repair.

## 23. Exception flow

Quarantine invalid signature, replay, unknown device/tenant, impossible coordinate, stale/out-of-order conflict, provider schema drift, rate overload or ambiguous retry. Record blocker/error/issue, preserve evidence and exact safe resume point; never hide or bypass failure.

## 24. Business rules

- Each non-AI integration is case-specific shared-product code under RPD-038.
- Raw provider events never directly mutate shipment state; canonical rules decide derived signals.
- Out-of-order/duplicate data is preserved and classified, not silently overwritten.
- Extend canonical Phase 3/4 records and source/version lineage; no silent re-entry or duplicate source of truth.
- When stock/quantity changes, use exact UOM and idempotent ledger/task events; normal roles never directly patch balances.
- RPD-022 prevents any tamper-proof/immutable-for-all claim; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Provider auth/schema/source ID/time/coordinate/accuracy and tenant-resource mapping are valid.
- Canonical link and retention/classification policies are deterministic.
- Derived milestone/exception cannot contradict authoritative confirmed events without review.
- Reject tenant/company/branch/warehouse/customer-owner/source/config/version mismatch and stale concurrent mutation.
- Every state, assignment, movement or external event must be authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Integration admins manage credentials/mappings; Operations sees authorized normalized events; customer projections expose only permitted shipment tracking; raw device/driver data is restricted. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Valid/invalid signature, duplicate/replay, late/out-of-order, unknown device, schema version, impossible/stale points, high-rate burst, multiple tenants and provider outage. Include deterministic IDs, exact quantities/UOM where relevant, source/config versions, allowed/denied roles, Tenant A/B, customer owners and retry/concurrency fixtures.

## 28. Tests to create/update

- Auth/schema/dedup/order/mapping/geofence/retention unit and integration tests.
- Webhook/job/retry/DLQ/API/milestone/exception/selective-realtime E2E tests.
- RLS/RBAC/location privacy, rate/load, observability and failure-recovery tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.
- Inventory equation/ledger/reconciliation or transport state/capacity/event-order tests wherever applicable.

## 29. Regression tests

API/webhook/job/security, PostGIS, fleet/resource, shipment timeline, customer tracking and incident response. Re-run relevant tenant/customer isolation, inventory/operational integrity, Finance/API compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant E2E, database reset/migration/type generation, security/dependency, job/integration and target-volume TMS/WMS commands. Do not disable a gate; separate proven pre-existing failures in `ERROR_LEDGER.md`.

## 31. Documentation to update

Provider-specific contract/credential/event mapping, privacy/retention, outage/schema-drift/replay runbook and canonical tracking API. Update persistent context/status/task/change/regression/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs plus release note when behavior changes.

## 32. Rollback/recovery note

Disable adapter/credentials, quarantine queue, preserve raw evidence within policy, restore last trusted mapping and replay only bounded verified events. State last trusted checkpoint, reversible steps, data/ledger/event reconciliation and exact resume command; do not use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Only authenticated mapped events affect canonical projections.
- Duplicates/order/retries cannot corrupt state.
- Load, privacy, retention and outage controls pass evidence gates.
- All mandatory automated/manual gates pass at one recorded checkpoint.
- Completion evidence maps source requirement → task → code/migration/contract/UI → test → documentation.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation summary; commands and baseline/after results; tenant/customer/access/inventory/transport/Finance evidence; idempotency/concurrency/reconciliation/performance results; residual errors/issues/risks; docs; rollback/resume; and recommended next task. Update all persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-227 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.

