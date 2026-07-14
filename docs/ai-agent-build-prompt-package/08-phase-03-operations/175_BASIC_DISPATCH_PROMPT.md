# Prompt 175 — Basic Dispatch

**Prompt ID:** `CG-S8-OPS-009`  
**Package document:** `CG-AABPP-OPS-175`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-175.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-009` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Dispatch; Epic: Shipment Release; Capability: Simple ready queue, dispatch, hold and reassignment; Feature slice: Planned/assigned shipment→dispatch check→dispatched/held/reassigned; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement basic shipment dispatch from a permission-safe readiness queue without advanced board, optimization or realtime fleet orchestration.

## 5. Business value

Release planned shipments with required assignment/doc/schedule controls and complete accountability.

## 6. Source requirement

OPS-TMS-001..004 basic Phase 3 slice; Charter/Delivery Operations MVP; Phase 3/5 split. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-169..174; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-176..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Dispatch schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend dispatch command/history, readiness snapshot, effective time, assignment reference, hold/reassign reason and idempotency/version constraints.

## 14. API impact

Provide shared REST/GraphQL ready-queue, readiness-check, dispatch, hold, release and reassign operations.

## 15. UI/UX impact

Build accessible server-paginated ready queue and shipment dispatch panel/list with blockers, quick actions and complete states; no advanced dispatch board.

## 16. Security impact

Apply branch/service/region/assignment scopes and protect driver/vendor/contact/location fields; bulk actions revalidate every record. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/status/branch/service/date/readiness; paginate/filter queues and make bulk commands bounded/idempotent.

## 18. Audit impact

Record readiness inputs/version, dispatcher, assignment, dispatch/hold/release/reassign time/reason and rejected bulk items.

## 19. Data migration impact

Map legacy dispatch state/history only with shipment/assignment/time evidence; ambiguous state remains blocked.

## 20. Detailed implementation tasks

1. Define dispatch readiness checklist, command states and Phase 5 boundary.
2. Implement indexed ready queue and deterministic readiness evaluation.
3. Implement atomic idempotent dispatch/hold/release/reassign including bounded bulk.
4. Build queue/panel/list UX and shared API contracts.
5. Verify access, lifecycle/milestone integration, concurrency, audit and performance.

## 21. Main flow

Dispatcher selects an eligible assigned shipment, passes readiness checks and dispatches it exactly once.

## 22. Alternative flow

Shipment is held/released or reassigned with reason before/after dispatch according to policy.

## 23. Exception flow

Missing assignment/document/schedule, active exception, stale state, bulk partial failure or unauthorized scope blocks affected records.

## 24. Business rules

- Phase 3 provides list/queue dispatch, not dispatch board, route/load/capacity optimization or telematics.
- Dispatch is a validated lifecycle command, not direct status edit.
- Bulk dispatch is per-record atomic/idempotent with explicit partial result.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate shipment state/version, active assignment, schedule, required docs and blocking exceptions.
- Recheck authorization/readiness at commit time.
- Dispatch/hold/release/reassign transitions reconcile with shipment lifecycle/history.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Dispatcher/ops manager acts within branch/service/region scope; customer/public views receive status only, never dispatch controls. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Ready/not-ready shipments, missing assignment/doc, active exception, concurrent dispatch, bulk mixed results and cross-scope records. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Readiness/dispatch/hold/reassign/idempotency/bulk/concurrency/database tests.
- RLS/RBAC/field/record/cross-tenant/API parity/audit tests.
- Queue/panel E2E, accessibility, pagination/bulk performance and advanced-scope regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Shipment lifecycle, assignments, milestones/exceptions, documents and Step 10 dispatch contracts. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-175.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Only ready authorized shipments dispatch exactly once.
- Queue and bulk behavior remain scoped and recoverable.
- No advanced planning/dispatch feature is smuggled into Phase 3.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-010` / `OPS-176` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

