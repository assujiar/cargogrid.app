# Prompt 169 — Shipment Order

**Prompt ID:** `CG-S8-OPS-003`  
**Package document:** `CG-AABPP-OPS-169`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-169.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-003` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Order Execution; Epic: Shipment Definition; Capability: Canonical Shipment Order; Feature slice: Confirmed Job Order→single-leg Shipment Order→planning readiness; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant-aware Shipment Orders linked to Job Order with parties, cargo, service, mode, route, schedule and governed quantity allocation.

## 5. Business value

Create an executable shipment definition that preserves quote/job data and can enter basic transport execution.

## 6. Source requirement

OPS-SHP-001..004 basic Phase 3 slice; shipment data dictionary; UX OPS-SHP-001. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-170..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Order Execution schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend shipment order/root, job link, number, shipper/consignee/notify references, cargo/package/dimension allocation, service/mode, origin/destination, schedule, status/version and uniqueness constraints.

## 14. API impact

Provide shared REST/GraphQL create-from-job, split-basic-allocation, update-draft, validate, confirm, search and read operations.

## 15. UI/UX impact

Build accessible Shipment Order list/detail/create-from-job workflow with inherited values, allocation balance, route/schedule fields and complete states.

## 16. Security impact

Apply tenant/branch/customer/service/owner scopes and field policy; customer party/location data and cost/selling projections are minimized. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/number/job/customer/status/service/mode/schedule; server-paginate lists and bound package/allocation calculations.

## 18. Audit impact

Record Job Order/source versions, allocations, party/location/service/cargo changes, confirmation, cancellation and downstream lifecycle links.

## 19. Data migration impact

Map existing shipments to Job Orders and canonical parties/statuses; preserve unresolved orphan records for reconciliation.

## 20. Detailed implementation tasks

1. Define Shipment Order identity, job cardinality, allocation and draft/confirm invariants.
2. Implement idempotent create-from-job and balanced shipment/cargo allocations.
3. Implement party/location/service/mode/schedule validation and governed draft changes.
4. Build list/detail/create workflow and shared API contracts.
5. Verify linkage, no-reentry, concurrency, access, migration and lifecycle readiness.

## 21. Main flow

Authorized user creates and confirms a single-leg Shipment Order from a confirmed Job Order using inherited parties/cargo/service data.

## 22. Alternative flow

Job cargo is split into multiple independent basic Shipment Orders with reconciled allocation and explicit reason.

## 23. Exception flow

Over-allocation, incompatible mode/service, missing party/site, stale job, duplicate reference or unauthorized scope blocks confirmation.

## 24. Business rules

- Every Shipment Order belongs to one Job Order and preserves source lineage.
- Allocated quantity/weight/volume cannot exceed the governed Job Order basis without approved override.
- Multi-leg/multimodal orchestration is excluded; each Phase 3 shipment is one basic execution unit.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate party roles, addresses/sites, cargo UOM/dimensions, service/mode and schedule consistency.
- Enforce allocation reconciliation, number uniqueness and allowed status transitions.
- Use PostGIS/reference locations where configured; do not copy unrestricted addresses.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Operations edits scoped drafts; customer/sales visibility is read-only and filtered; sensitive financial/vendor data remains protected. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

One/multiple shipments per job, balanced/over allocation, land/air/sea, missing sites, duplicate references, stale versions and two tenants. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Job-shipment FK/allocation/number/status/concurrency/database tests.
- RLS/RBAC/field/record/cross-tenant/API parity/audit tests.
- Create/list/detail E2E, accessibility, pagination and no-reentry regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Job Order, customer/party/site/cargo/service masters, later milestone/ePOD and Commercial source snapshots. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-169.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Shipment Order is fully linked, balanced and confirmation-ready.
- Customer/cargo/service data is inherited with provenance.
- Advanced TMS/WMS scope is not introduced.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-004` / `OPS-170` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

