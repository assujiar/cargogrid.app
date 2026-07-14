# Prompt 179 — Basic Job Profitability

**Prompt ID:** `CG-S8-OPS-013`  
**Package document:** `CG-AABPP-OPS-179`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-179.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-013` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Operational Cost; Epic: Operational Margin View; Capability: Basic revenue-versus-actual-cost profitability; Feature slice: Pinned Commercial revenue + approved actual cost→operational margin snapshot; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement basic operational job profitability using pinned Commercial revenue and approved actual cost with exact, permission-safe calculations.

## 5. Business value

Expose cost variance and margin erosion before job close while preserving the boundary to accounting P&L.

## 6. Source requirement

OPS-CST-001..004 basic Phase 3 slice; COM-150/156; Brief/Charter profitability; Phase 4 boundary. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-178; verified Commercial revenue/pricing snapshot; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-180..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Operational Cost schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend profitability snapshot/version, revenue source/version, approved cost version, exact amount/currency, margin result, calculation/rounding version and status.

## 14. API impact

Provide shared REST/GraphQL calculate/recalculate, read, explain and authorized override-as-new-snapshot operations.

## 15. UI/UX impact

Build permission-aware job profitability summary/detail with source versions, cost variance, margin and explicit operational—not accounting—label.

## 16. Security impact

Revenue/cost/margin fields use restricted server policy; aggregates/exports cannot reveal hidden values. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/job/status/calculated time; calculate incrementally/bounded and batch via durable jobs when volume requires.

## 18. Audit impact

Record revenue/cost/rule/rounding inputs, output, calculation actor/job, override/recalculation reason and snapshot used downstream.

## 19. Data migration impact

Backfill only when revenue/cost/currency versions reconcile; otherwise label historical profitability unverifiable.

## 20. Detailed implementation tasks

1. Define operational profitability formula, exact money and accounting boundary.
2. Implement deterministic snapshot calculation from pinned Commercial revenue and approved costs.
3. Implement recalculation/override as new snapshot with reason and access control.
4. Build summary/detail explanation UX and shared API contracts.
5. Verify precision, reconciliation, field security, performance and Phase 4 compatibility.

## 21. Main flow

System calculates a reproducible operational margin snapshot from one revenue version and one approved actual-cost version.

## 22. Alternative flow

Authorized recalculation/override creates a new explained snapshot after source correction.

## 23. Exception flow

Mixed/unknown currency, missing/unclear source, unapproved cost, stale version or unauthorized access returns explicit unavailable/blocked.

## 24. Business rules

- This is operational profitability, not GL/subledger/accounting P&L or recognized revenue.
- Money and rounding reuse governed exact calculation rules.
- Historical snapshots remain linked; source changes do not silently rewrite them.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate source job/customer/service, currency, revenue/cost versions and exact reconciliation.
- Margin amount/percent formulas are named and consistent with Commercial semantics.
- Any FX use requires explicit source/date/version; otherwise cross-currency result is unavailable.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Authorized operations/management/finance-read roles see scoped results; cost/revenue/margin fields remain hidden elsewhere. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Positive/zero/negative margin, cost overrun, missing/unapproved cost, mixed currency, recalculation, hidden fields and multiple tenants. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Profit formula/precision/source-version/snapshot/recalculation/database tests.
- RLS/RBAC/field/record/aggregate-inference/API parity/audit tests.
- Summary/detail E2E, accessibility, batch performance and Commercial/actual-cost regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Commercial margin/pricing, actual costs, dashboard/reports, billing readiness and future Phase 4 profitability. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-179.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Operational profitability is exact, explainable and source-versioned.
- Users cannot mistake it for accounting P&L or infer restricted money.
- Phase 4 can consume/reconcile the snapshot without re-entry.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-014` / `OPS-180` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

