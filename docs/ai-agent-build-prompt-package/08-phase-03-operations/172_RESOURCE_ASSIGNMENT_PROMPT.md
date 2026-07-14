# Prompt 172 — Resource and Vendor Assignment

**Prompt ID:** `CG-S8-OPS-006`  
**Package document:** `CG-AABPP-OPS-172`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-172.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-006` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Shipment Execution; Epic: Execution Responsibility; Capability: Basic vendor, fleet, vehicle and driver assignment; Feature slice: Eligible shipment→permitted resource references→assigned execution owner; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement basic shipment assignment to verified vendor/fleet/vehicle/driver/resource references with availability and conflict checks.

## 5. Business value

Establish accountable execution ownership without building fleet, driver or vendor lifecycle domains prematurely.

## 6. Source requirement

OPS-TMS-001..004 basic Phase 3 slice; Brief TMS assignment; Phase 5/6 boundaries. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168..171; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-173..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Shipment Execution schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend assignment root/history, resource type/reference, validity/availability snapshot, effective time, status, reason and optimistic/idempotent constraints.

## 14. API impact

Provide shared REST/GraphQL candidate search, assign, reassign, unassign, hold and assignment-history operations.

## 15. UI/UX impact

Build accessible assignment panel/queue with scoped candidate lookup, availability warnings, conflict/reason handling and complete states.

## 16. Security impact

Candidate lookup and assignment require tenant/branch/service/region permissions; protect driver PII, vendor data and hidden capacity information. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/shipment/resource/effective/status; bound candidate lookup/conflict windows and avoid full fleet/vendor datasets.

## 18. Audit impact

Record candidate criteria where lawful, selected resource/version, actor, assignment/reassignment reason, availability evidence and conflicts.

## 19. Data migration impact

Map legacy resource assignments to canonical references when resolvable; orphan/expired references stay blocked for reconciliation.

## 20. Detailed implementation tasks

1. Define assignment types, resource ownership boundary, eligibility and conflict semantics.
2. Implement scoped candidate lookup against existing canonical references without new master lifecycle.
3. Implement atomic assign/reassign/unassign/hold with concurrency/idempotency.
4. Build assignment UX and shared API contracts.
5. Verify PII/access, conflicts, lifecycle, audit and Step 5/6 extensibility.

## 21. Main flow

Authorized dispatcher assigns eligible verified references to a planned shipment and moves it toward dispatch readiness.

## 22. Alternative flow

Resource is reassigned or held with reason after availability/conflict change while history remains complete.

## 23. Exception flow

Expired/unavailable/inaccessible resource, overlap conflict, stale shipment or missing service qualification blocks assignment.

## 24. Business rules

- Phase 3 references resources; it does not own vendor onboarding, fleet/driver master lifecycle, sourcing or capacity optimization.
- Assignment history is append-oriented and effective-dated.
- One active assignment per required role/effective slot unless an explicit compatible rule permits otherwise.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate resource status, service/mode/region capability, date validity and tenant/organization relationship.
- Detect overlapping active assignments and stale resource snapshots.
- Reassignment requires reason and preserves prior outcome/effects.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Dispatcher/ops manager assigns within scope; driver/vendor PII and cost fields require explicit permission; public/customer views are minimized. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Internal/vendor resources, valid/expired/unavailable references, overlapping assignments, reassignment/hold, PII restrictions and two tenants. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Assignment eligibility/conflict/history/idempotency/concurrency/database tests.
- RLS/RBAC/field/record/PII/cross-tenant/API parity/audit tests.
- Assignment panel/queue E2E, accessibility, candidate lookup performance and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Shipment lifecycle/modes, canonical vendor/rate foundation, future fleet/driver/procurement and dispatch. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-172.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Assignments are valid, conflict-safe and fully auditable.
- No unauthorized resource/PII data is exposed.
- No duplicate vendor/fleet/driver domain is created.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-007` / `OPS-173` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

