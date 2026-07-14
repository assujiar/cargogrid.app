# Prompt 185 — Operations Integrated Verification

**Prompt ID:** `CG-S8-OPS-019`  
**Package document:** `CG-AABPP-OPS-185`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-185.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-019` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Operations Completion; Epic: Integrated Verification; Capability: Cross-capability Operations verification; Feature slice: All capability evidence→critical shipment E2E→reconciled verification report; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Independently verify all seventeen Operations capabilities at one repository/schema/environment checkpoint before hardening.

## 5. Business value

Expose cross-capability shipment, tenant, evidence, cost and lineage failures that isolated tests miss.

## 6. Source requirement

OPS-SHP/TMS/TRK/DOC/CST-001..004 basic slices; Master Prompt Phase 3/critical E2E; OPS-168..184. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168..184 VERIFIED; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-186..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Operations Completion schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

No feature schema by default; inspect migrations, constraints, RLS, lifecycle/events, files/ePOD, money, lineage and readiness records.

## 14. API impact

Verify REST/GraphQL parity, contracts, field policies, idempotency, jobs/webhooks, file access, tracking and Finance handoff.

## 15. UI/UX impact

Execute complete desktop/responsive/accessibility states for Job, Shipment, modes, assignment, milestone, exception, dispatch, document/ePOD, cost, tracking and readiness.

## 16. Security impact

Run cross-tenant/customer, branch/service, assignment, field/record, public-token, file/ePOD, cost/profitability and privileged-access negative matrices. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Test lists/timelines/event ingestion/dispatch/document upload/tracking/dashboard/report/readiness at realistic volume and budgets.

## 18. Audit impact

Reconcile material create/transition/assignment/event/exception/dispatch/ePOD/cost/override/readiness/privileged actions to source versions.

## 19. Data migration impact

Rebuild and upgrade from supported checkpoints; reconcile seeds/config, legacy mapping, rollback/forward-fix and no destructive drift.

## 20. Detailed implementation tasks

1. Freeze one trusted checkpoint and inventory evidence for OPS-168..184.
2. Run accepted quote→Job→Shipment→dispatch/milestone→delivery/ePOD→actual cost→billing readiness E2E.
3. Run tenant/customer/access/financial/lineage/API/UI/job/file/public-tracking/performance matrices.
4. Reconcile requirements, WBS, ledgers, errors/issues, advanced-scope audit and residual risk.
5. Produce ranked failures and mark OPS-186 ready only when evidence is trustworthy.

## 21. Main flow

All capability and cross-flow gates pass at one checkpoint with reproducible evidence.

## 22. Alternative flow

Noncritical evidence gap becomes a bounded task with owner/dependency while phase stays partial.

## 23. Exception flow

Tenant/customer leak, invalid lifecycle, duplicate Job, ePOD exposure, money mismatch, missing lineage/readiness or critical migration/security failure blocks hardening.

## 24. Business rules

- Package completeness is not runtime verification.
- No test/evidence is weakened or invented to obtain pass.
- RPD-022, online-first and direct-GA risks remain disclosed even when tests pass.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Reconcile 17 capabilities, 20 Phase 3 requirement anchors and every runtime task/evidence path.
- Critical flow preserves exact Commercial source and Operations evidence lineage.
- All mandatory failures have severity, owner, root cause and exact resume prompt.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Use authorized isolated fixtures; no production/customer data or shared-environment mutation without authority. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

At least two tenants/customers, multiple organizations/roles, land/air/sea flows, exception/ePOD/cost/readiness cases and realistic volume. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Full database/migration/RLS/RBAC/field/record/API/job/file/audit suites.
- Critical E2E, concurrency/idempotency/retry, public/customer security, accessibility/browser and performance suites.
- Brownfield/no-reentry/lineage/contract-compatibility/forbidden-scope and smoke/regression suites.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Platform Core, Commercial handoff, all Operations capabilities, accepted-risk disclosures and Step 9 boundary. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-185.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Integrated evidence covers every capability and Phase 3 requirement anchor.
- Critical flow, isolation, files/ePOD, cost and readiness pass.
- Every remaining issue correctly blocks or permits hardening.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-020` / `OPS-186` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

