# Prompt 182 — Operations Dashboard

**Prompt ID:** `CG-S8-OPS-016`  
**Package document:** `CG-AABPP-OPS-182`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-182.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-016` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Operations Analytics; Epic: Control Tower Insight; Capability: Role-specific Operations dashboard; Feature slice: Scoped live jobs/shipments/milestones/exceptions/ePOD/readiness→drill-down; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement role-specific live Operations dashboards for shipment status, milestone SLA, exceptions, ePOD completion, cost variance and billing readiness.

## 5. Business value

Give Operations and management actionable visibility from reconciled canonical transactions.

## 6. Source requirement

OPS-SHP/TMS/TRK/DOC/CST-004 basic slices; Brief §13; RPD-014. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168..181; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-183..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Operations Analytics schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add only governed read views/functions/indexes or cache metadata required by measured queries; transactions/events remain authoritative.

## 14. API impact

Provide permission-aware shared REST/GraphQL dashboard queries with metric definitions, filters, time zone, pagination, timeout and drill-down locators.

## 15. UI/UX impact

Build accessible desktop/responsive dashboard with KPI cards, status/aging/exception/ePOD/readiness queues, filters, map only when justified and complete states.

## 16. Security impact

Aggregate after tenant/row/field/customer policy; protect precise locations, vendor/driver PII, cost/profitability and hidden exceptions. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Follow RPD-014 live OLTP controls: read-only queries, indexes, query budgets, timeouts, caching, server pagination and threshold-driven replicas.

## 18. Audit impact

Record privileged dashboard/export access, saved filter/config and metric-definition changes; use proportionate telemetry for normal views.

## 19. Data migration impact

No transaction migration; version metric definitions and invalidate stale cache/saved filters safely.

## 20. Detailed implementation tasks

1. Define every KPI, grain, filters, time zone, source and reconciliation rule.
2. Implement permission-safe bounded live queries, indexes/cache and drill-down locators.
3. Build role-specific dashboard/action queues and safe map/timeline summaries.
4. Add query observability, budgets, stale/error behavior and authorized export links.
5. Verify reconciliation, inference resistance, accessibility, volume and regression.

## 21. Main flow

Authorized user sees reconciled scoped operational metrics and drills into exact permitted jobs/shipments/evidence.

## 22. Alternative flow

Cached snapshot is used within freshness policy with visible as-of time and safe refresh.

## 23. Exception flow

Timeout, stale cache, mixed-currency ambiguity, hidden-row inference or unavailable source returns a safe explicit state.

## 24. Business rules

- Every metric has owner, definition, grain, time zone and source IDs.
- Dashboard is not a new source of truth.
- Aggregates never weaken underlying row/field/customer permissions.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Reconcile KPI/queue counts and amounts to accessible canonical source samples.
- Validate filters, time zone, as-of/freshness and currency labeling.
- Drill-down matches displayed permitted aggregate.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Dispatcher/ops manager/executive views differ by scope; location/PII/cost/profitability/customer data remains field-protected. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Multiple tenants/branches/customers, all lifecycle states, overdue milestones, exceptions, ePOD/readiness, hidden costs/locations and high volume. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Metric/query/reconciliation/filter/cache/timeout tests.
- RLS/RBAC/field/record/customer/aggregate-inference/API parity/audit tests.
- Dashboard/drill-down E2E, WCAG/browser/responsive and performance-budget tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

All Operations transactions, tracking, reports, live-query guards and server pagination. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-182.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Dashboard reconciles to canonical authorized Operations data.
- No hidden record/value/location can be inferred.
- Performance and accessibility budgets pass at realistic volume.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-017` / `OPS-183` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

