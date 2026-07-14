# Prompt 158 — Commercial Dashboard

**Prompt ID:** `CG-S7-COM-017`  
**Package document:** `CG-AABPP-COM-158`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-158.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-017` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Commercial Analytics; Epic: Actionable Sales Insight; Capability: Role-specific Commercial dashboard; Feature slice: Scoped live metrics→drill-down→action queue; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement role-specific live Commercial dashboards for lead aging, activities, pipeline, costing/quote SLA, margin, win/loss and forecast with permission-safe drill-down.

## 5. Business value

Let sellers and managers act from reconciled live metrics instead of stale spreadsheets.

## 6. Source requirement

COM-LEAD/CRM/OPP/QTN/CPR-004; Brief §13; UX Commercial Dashboard; RPD-014. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-143..157; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-159..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Commercial Analytics schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add only necessary governed read views/functions/indexes or cache metadata; transactional records remain authoritative and no duplicate analytics store is introduced by default.

## 14. API impact

Provide permission-aware shared REST/GraphQL dashboard queries with documented metric definitions, filters, pagination, timeouts and drill-down locators.

## 15. UI/UX impact

Build accessible responsive dashboard with KPI cards, aging/activity queues, pipeline/quote panels, filters, drill-down and complete loading/empty/error/stale states.

## 16. Security impact

Metrics and aggregates apply row/field policy before aggregation; protect margin/cost/credit/forecast and prevent count-based inference. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Follow RPD-014 live OLTP controls: read-only queries, indexes, query budgets, timeouts, caching, server pagination and threshold-driven replicas.

## 18. Audit impact

Record privileged dashboard/export access, saved filter/config changes and metric-version changes; ordinary views use proportionate security telemetry.

## 19. Data migration impact

No transaction migration; version metric definitions and safely invalidate prior caches/saved filters.

## 20. Detailed implementation tasks

1. Define each KPI, grain, filters, time zone, currency and source reconciliation rule.
2. Implement permission-safe bounded dashboard query services and indexes/cache.
3. Implement role-specific layout, action queues and drill-down to canonical records.
4. Add observability, query budgets, stale/error behavior and exports where authorized.
5. Verify reconciliation, hidden-row inference, accessibility, performance and regression.

## 21. Main flow

Authorized user opens a scoped dashboard, sees reconciled metrics and drills into the exact permitted source records.

## 22. Alternative flow

Saved filters/time windows and cached results are used within freshness policy with visible as-of time.

## 23. Exception flow

Query timeout, stale cache, hidden-row risk, missing metric source or mixed-currency ambiguity returns a safe explicit state.

## 24. Business rules

- Every metric has owner, definition, grain, time zone, currency and source IDs.
- Dashboard is operational insight, not a new source of truth.
- Aggregates never weaken underlying row/field permissions.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Reconcile cards/charts/queues to accessible transactional samples and report definitions.
- Validate filter scope, time zone, currency and as-of/freshness.
- Drill-down count and amount must match the displayed permitted aggregate.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Seller/manager/executive dashboards differ by role/scope; cost/margin/credit/forecast components remain field-protected. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Multiple tenants/branches/teams, hidden high-value records, aging/SLA boundaries, mixed currencies/time zones, stale cache and large volumes. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Metric definition/query/reconciliation/filter/cache/timeout tests.
- RLS/RBAC/field/record/aggregate-inference/API parity/audit tests.
- Dashboard/drill-down/action E2E, WCAG/browser, responsive and performance-budget tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

All Commercial transactions, CRM forecast, reports, live-query guards and server pagination. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-158.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Dashboard metrics reconcile to canonical authorized data.
- No hidden record/value can be inferred through aggregates or drill-down.
- Performance and accessibility budgets pass at realistic volume.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-018` / `COM-159` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

