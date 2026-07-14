# Prompt 159 — Commercial Reports

**Prompt ID:** `CG-S7-COM-018`  
**Package document:** `CG-AABPP-COM-159`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-159.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-018` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Commercial Analytics; Epic: Governed Reporting; Capability: Commercial reports and exports; Feature slice: Defined report→scoped query→preview/export/schedule→evidence; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement governed Commercial reports for conversion, aging, activity, pipeline, forecast, costing, quote SLA, win/loss, pricing and margin with safe export.

## 5. Business value

Provide reproducible management evidence without ad-hoc database access or sensitive data leakage.

## 6. Source requirement

COM-LEAD/CRM/OPP/QTN/CPR-004; Brief §13; coverage report catalogue; RPD-014. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-143..158; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-160..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Commercial Analytics schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add only approved read views/functions/indexes and report-run metadata; report definitions are versioned and transactional sources remain authoritative.

## 14. API impact

Provide shared REST/GraphQL report definition, parameter validation, preview, async export, schedule and run-status operations.

## 15. UI/UX impact

Build accessible report catalogue/parameter/preview/run-history UI with server pagination, column/field policy and complete job states.

## 16. Security impact

Apply row/field policy to preview/export/schedule delivery; exported files are private, scanned, expiring and audited; prevent formula injection. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Use read-only queries, budgets/timeouts, async PostgreSQL job framework for large exports, bounded retention and threshold-driven replicas.

## 18. Audit impact

Record definition/version, parameters/scope, requester, row count, sensitive columns, run/result access, schedule and expiry/deletion.

## 19. Data migration impact

Version existing report definitions and retire unsafe exports; no transaction migration.

## 20. Detailed implementation tasks

1. Define named reports, metric/grain/parameter/column ownership and source reconciliation.
2. Implement safe query services, preview and asynchronous export/schedule jobs.
3. Implement permission-aware formats, formula-injection controls and private result lifecycle.
4. Build catalogue/preview/history UX and shared API contracts.
5. Verify reconciliation, access, job recovery, file security, performance and retention.

## 21. Main flow

Authorized user runs a scoped report, previews reconciled rows and receives a private export when requested.

## 22. Alternative flow

Scheduled report runs asynchronously and delivers only to still-authorized recipients under current scope.

## 23. Exception flow

Invalid range, excessive query, revoked permission, job failure, formula injection or expired result fails safely.

## 24. Business rules

- Report definition/version and source lineage are explicit.
- Export never expands access beyond interactive view and rechecks permission at execution/download.
- Large reports are asynchronous; browser full-dataset export is forbidden.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Validate parameters, maximum ranges, columns, currency/time zone and definition version.
- Reconcile totals/rows to canonical permitted source data.
- Sanitize cells/filenames and enforce result expiry/retention.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Catalogue, columns, rows, schedules and recipients use entitlement/RBAC/scope/field policy; sensitive commercial exports require explicit permission. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Large/small datasets, hidden columns/rows, mixed currencies/time zones, scheduled recipient revocation, job retry and malicious cell values. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Definition/parameter/query/reconciliation/export/schedule/job/idempotency tests.
- RLS/RBAC/field/record/file/signed-URL/formula-injection/API/audit tests.
- Catalogue/preview/history/download E2E, accessibility, load/query-budget and dashboard regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Commercial dashboards, import/export/job/file engines, metrics and existing report contracts. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-159.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Reports reconcile, are reproducible and stay within current access.
- Exports are private, safe, bounded and recoverable.
- No report creates an ungoverned analytics copy or browser dataset.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-019` / `COM-160` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

