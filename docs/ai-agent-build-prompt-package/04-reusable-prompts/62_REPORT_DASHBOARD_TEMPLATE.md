# Template 62 — Report and Dashboard

**Prompt ID:** `CG-S4-REUSE-010`  
**Package document:** `CG-AABPP-REUSE-062`  
**Version:** `0.5.0`  
**Intended use:** Implement one permission-aware report, metric set or dashboard slice.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Reporting and Analytics.

## 4. Objective

Implement {{REPORT_OR_DASHBOARD}} with governed metric definitions, tenant/field/record access and bounded live-OLTP reads.

## 5. Business value

Provide trustworthy decision evidence without leaking data or destabilizing transactional workloads.

## 6. Source requirement

{{REPORT_REQUIREMENT_IDS}}, {{METRIC_DEFINITION_IDS}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`, approved ADRs/migrations/contracts, verified runtime gates and baseline evidence. All must be satisfied or explicitly blocking.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; normally 5–15 files, one module boundary and at most 1–3 approved migrations. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, lockfiles unless dependency scope is explicit, secrets, generated artifacts unless authorized, tenant data, and broad refactors.

## 13. Database impact

Use approved read model/view/query with tenant-leading indexes; materialization requires freshness/refresh/ownership plan.

## 14. API impact

Provide bounded filters, cursor/server pagination, export/asynchronous generation and stable metric metadata.

## 15. UI/UX impact

Complete dashboard/report states, filter context, freshness/timezone/currency labels, accessible tables/charts and drill-down authorization.

## 16. Security impact

Apply row/field/export/search/report permissions; prevent inference, broad aggregation and signed-file leakage.

## 17. Performance impact

Primary scope: query/bundle/render budgets, filter cardinality, caching/revalidation and live-OLTP concurrency guards.

## 18. Audit impact

Audit sensitive report access, export generation/download, scheduled recipients and configuration changes.

## 19. Data migration impact

Read-model backfill/refresh is versioned, tenant-scoped, idempotent and reconciled if required.

## 20. Detailed implementation tasks

1. Define metric grain, formula, source, filters, timezone/currency, freshness and reconciliation owner.
2. Implement permission-aware query/read model and bounded REST/GraphQL/report job contract.
3. Build accessible view with states, filters, pagination, drilldown and export/schedule behavior.
4. Measure query plans/latency/payload/concurrency and reconcile totals against system of record.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Authorized user views correctly scoped reconciled metrics with clear freshness and filters.

## 22. Alternative flow

Saved view, drilldown, schedule or async export preserves the same definition and access.

## 23. Exception flow

No data, stale data, partial source, unauthorized dimension, timeout and export failure are visible/recoverable.

## 24. Business rules

- One governed metric definition is reused across UI/API/export.
- Live OLTP dashboards require explicit query/concurrency guards; heavy reports are asynchronous.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Totals, grain, currency/rounding/timezone and filter interactions reconcile.
- Freshness and partial-data status cannot be hidden.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Test row, field, aggregate, drilldown, export and scheduled-recipient access across tenants.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Two tenants, multiple scopes, empty/large/skewed datasets, currencies/timezones, stale/partial data and restricted dimensions. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Metric calculation/reconciliation, query/API, component/chart/table/accessibility and export/schedule tests.
- Cross-tenant/field inference negatives, query plan/latency/concurrency and E2E tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Transactional performance, existing metric definitions, exports, saved views and affected domain reports.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Metrics reconcile to canonical sources and access is consistent across view/API/export.
- Performance, freshness, accessibility and failure evidence passes.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
