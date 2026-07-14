# Prompt 173 — Milestone Management

**Prompt ID:** `CG-S8-OPS-007`  
**Package document:** `CG-AABPP-OPS-173`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-173.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-007` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Control Tower; Epic: Shipment Visibility; Capability: Milestone, ETA/ETD and timeline events; Feature slice: Configured milestone→idempotent event→status/timeline/notification projection; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement configurable shipment milestones and append-oriented event capture with ETA/ETD, location, source and reliable timeline projection.

## 5. Business value

Provide trustworthy operational visibility and downstream status/notification triggers.

## 6. Source requirement

OPS-TRK-001..004 basic Phase 3 slice; Brief shipment monitoring; BPR/UX Operations flow. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-169..172; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-174..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Control Tower schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend milestone definition/version, expected/actual event, event/received time, location/PostGIS, source/actor, correlation/idempotency, sequence and projection constraints.

## 14. API impact

Provide shared REST/GraphQL/manual/import/webhook milestone ingestion, correction-as-event, list/timeline and status projection operations.

## 15. UI/UX impact

Build accessible timeline/update form and control-tower queue with expected/actual, delay signal, source, map-safe location and complete states.

## 16. Security impact

Enforce shipment/customer/assignment scope; external ingestion authenticates source and location visibility is field/record restricted. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/shipment/code/event time/status/source; cursor-paginate events and handle high-volume ingestion with durable jobs where justified.

## 18. Audit impact

Milestone events themselves preserve source/time/actor/reason/correlation; record correction links, projection updates and notifications.

## 19. Data migration impact

Map legacy status histories into milestone events only with deterministic codes/times; preserve unknown events separately.

## 20. Detailed implementation tasks

1. Define versioned milestone templates by service/mode and projection rules.
2. Implement idempotent event ingestion with event/received time, ordering and correction semantics.
3. Implement ETA/ETD/location/status/notification projections through shared services.
4. Build timeline/update/queue UX and API contracts.
5. Verify out-of-order/duplicate events, access, scale, audit and lifecycle reconciliation.

## 21. Main flow

Authorized source posts one milestone event; timeline and allowed shipment status/notification projections update exactly once.

## 22. Alternative flow

Late/out-of-order event is accepted under policy and projections recalculate deterministically with visible received time.

## 23. Exception flow

Duplicate key, invalid sequence/code, inaccessible shipment, impossible time/location or projection conflict fails/reconciles safely.

## 24. Business rules

- Operational events are append-oriented; corrections link new evidence instead of silently rewriting history.
- Event time and received time are distinct and retained.
- Milestone display labels may vary; canonical code and projection semantics remain stable.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate code/template version, shipment state, source authority, timestamps, location bounds and idempotency.
- Projection must be deterministic under duplicate/out-of-order/replay.
- Customer-visible timeline excludes internal/sensitive events and locations by policy.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Assigned/internal users update permitted milestones; integrations use scoped credentials; customers/public see sanitized events only. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Expected/actual/out-of-order/duplicate/corrected events, delays, locations, multiple sources, restricted internal milestones and two tenants. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Milestone version/event/idempotency/order/projection/location database tests.
- RLS/RBAC/field/record/webhook/API parity/cross-tenant/audit tests.
- Timeline/update/queue E2E, accessibility, high-volume cursor performance and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Shipment lifecycle, assignment, notifications, tracking, exceptions, PostGIS and later advanced TMS ingestion. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-173.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Milestones are idempotent, ordered/reconciled and fully traceable.
- Shipment projection remains correct under retry/out-of-order events.
- Customer/public visibility cannot expose internal events or locations.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-008` / `OPS-174` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

