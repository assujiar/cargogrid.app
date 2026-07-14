# Prompt 178 — Actual Cost

**Prompt ID:** `CG-S8-OPS-012`  
**Package document:** `CG-AABPP-OPS-178`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-178.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-012` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Operational Cost; Epic: Shipment Cost Capture; Capability: Exact componentized actual cost and variance; Feature slice: Assignment/event/document source→actual cost component→approval/variance; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement componentized exact actual-cost capture, source/rate lineage, approval and estimated-versus-actual variance without Finance posting.

## 5. Business value

Give Operations timely cost control and a reliable input to basic profitability and later AP.

## 6. Source requirement

OPS-CST-001..004 basic Phase 3 slice; Brief Costing; UAT-E2E-015; financial integrity guardrails. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168..177; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-179..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Operational Cost schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend tenant/job/shipment cost root/component, category, vendor/internal source, rate/assignment/document refs, exact amount/currency, quantity/UOM, version/status, approval and variance constraints.

## 14. API impact

Provide shared REST/GraphQL create/update-draft, import, submit, approve/reject, adjust-as-new-version, totals and variance operations.

## 15. UI/UX impact

Build permission-aware actual-cost workbench with component lines, source links, estimated comparison, approval status and complete states.

## 16. Security impact

Cost/vendor/variance fields and approve/export actions use server field/record policy; customer/public projections expose none. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/job/shipment/vendor/status/category; bound component counts, calculate server-side and use async import for large inputs.

## 18. Audit impact

Record every source/rate/assignment/document, component before/after, formula/rounding/currency, approval/rejection, variance and adjustment reason.

## 19. Data migration impact

Backfill legacy cost only when amount/currency/source/job linkage is provable; unknown costs stay explicitly unreconciled.

## 20. Detailed implementation tasks

1. Define exact cost component, source, currency/rounding, status and approval semantics.
2. Implement server totals/variance with source lineage and optimistic versioning.
3. Implement submit/approval/adjustment and async import controls.
4. Build cost workbench and shared API contracts with restricted projections.
5. Verify precision, access, concurrency, audit, profitability and Phase 4/6 boundaries.

## 21. Main flow

Authorized Operations user records sourced cost components; approver validates exact totals/variance and approves the version.

## 22. Alternative flow

Approved cost is adjusted through a new reasoned version or imported asynchronously with row-level reconciliation.

## 23. Exception flow

Missing source/currency, stale version, invalid amount/UOM, duplicate component, unauthorized approval or import partial failure blocks safely.

## 24. Business rules

- Money uses exact decimals, explicit currency and versioned rounding; no floating point.
- Phase 3 records operational costs only—no vendor bill, AP, tax, journal, payment or settlement.
- Issued/approved cost versions are not silently overwritten; adjustments preserve lineage.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Reconcile component quantity×rate/minimum/surcharge and total/variance server-side.
- Validate vendor/internal source, shipment/job/assignment relationship, currency and approval authority.
- Prevent duplicate source/component/idempotency entries.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Operations enters permitted cost; approvers view/decide by scope; sellers/customers/public cannot infer restricted cost. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Estimated/actual components, minimum/surcharge, multiple currencies, adjustments, duplicate sources, import partial errors and restricted users. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Decimal/rounding/component/total/variance/version/approval/import/database tests.
- RLS/RBAC/field/record/cross-tenant/API parity/audit tests.
- Cost workbench/approval/import E2E, accessibility, batch performance and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Commercial rate/revenue snapshots, assignments, shipment/ePOD, future AP/vendor matching and reports. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-178.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Approved actual cost is exact, componentized and source-traceable.
- Sensitive costs never leak to unauthorized surfaces.
- No Finance or full Procurement posting scope is introduced.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-013` / `OPS-179` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

