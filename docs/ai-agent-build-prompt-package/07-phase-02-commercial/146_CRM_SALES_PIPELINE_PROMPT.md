# Prompt 146 — CRM Sales Plan and Pipeline

**Prompt ID:** `CG-S7-COM-005`  
**Package document:** `CG-AABPP-COM-146`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-146.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-005` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Customer Relationship; Epic: CRM Workspace; Capability: CRM sales plan, targets, pipeline and forecast; Feature slice: Plan→target→pipeline view→forecast→win/loss analysis; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a Commercial CRM workspace for sales plans, targets, governed pipeline views, forecast snapshots and win/loss analysis over canonical records.

## 5. Business value

Give sales teams actionable planning and pipeline visibility without parallel spreadsheets or duplicate transaction data.

## 6. Source requirement

COM-CRM-001..004; Brief §7.1 CRM; UX Commercial workspace/dashboard. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-143..145; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-147..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Customer Relationship schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend tenant/company/branch/team-scoped sales plan, target, forecast snapshot, category and win/loss reason entities referencing canonical leads/prospects/opportunities rather than copying them.

## 14. API impact

Expose permission-aware shared REST/GraphQL operations for plan/target lifecycle, pipeline aggregations, forecast snapshot and win/loss capture.

## 15. UI/UX impact

Build accessible CRM workbench with plan/target views, server-backed pipeline/forecast panels, drill-down, filters and complete desktop-first/responsive states.

## 16. Security impact

Apply own/team/department/branch/company scopes; forecast, target and selling-value fields require explicit access; aggregation cannot reveal hidden rows. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Use bounded live OLTP read models under RPD-014 with indexes, timeouts, caching and query budgets; no full dataset in browser.

## 18. Audit impact

Record plan/target/version/effective-date changes, forecast snapshot inputs, manual override reasons and win/loss categorization.

## 19. Data migration impact

Map legacy plans/targets only when ownership, period, currency and source are deterministic; retain source references.

## 20. Detailed implementation tasks

1. Define CRM planning boundaries and canonical pipeline/forecast metric definitions.
2. Implement versioned plans/targets and governed effective periods.
3. Build permission-safe pipeline aggregation and forecast snapshots over canonical data.
4. Implement win/loss reasons, override controls and CRM workbench UX/API.
5. Verify metric reconciliation, access inference, performance, audit and documentation.

## 21. Main flow

Manager publishes a scoped sales plan/target and reviews a reconciled pipeline/forecast built from authorized canonical records.

## 22. Alternative flow

An authorized forecast override creates a reasoned version without changing source opportunities.

## 23. Exception flow

Overlapping plan, invalid period/currency, hidden-row inference, stale snapshot or query-budget breach fails safely.

## 24. Business rules

- Plans/targets are versioned and effective-dated; source opportunities remain authoritative.
- Forecast formulas and manual overrides are explicit and auditable.
- Aggregates respect the same row/field permissions as drill-down records.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Validate period overlap, organizational scope, target currency/unit and published version.
- Reconcile aggregate counts/amounts to accessible source rows.
- Win/loss requires canonical reason and closure evidence where configured.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Managers administer permitted scopes; sellers see assigned targets and authorized pipeline; sensitive forecasts and values use field policy. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Multiple teams/branches, overlapping plans, mixed currencies, won/lost/open pipeline, hidden high-value records and override scenarios. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Plan/version/target/forecast metric and reconciliation tests.
- RLS/RBAC/field/record/aggregate-inference/API parity/audit tests.
- CRM workbench E2E, accessibility, query-budget/cache/pagination and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Lead/prospect/contact, opportunity read contracts, report metrics, configuration engines and live-query controls. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-146.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- CRM plans and forecasts reconcile to canonical scoped records.
- No spreadsheet copy or unauthorized aggregate leakage is introduced.
- Workbench remains responsive and auditable under realistic data volume.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-006` / `COM-147` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

