# Prompt 183 — Operations Reports

**Prompt ID:** `CG-S8-OPS-017`  
**Package document:** `CG-AABPP-OPS-183`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-183.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-017` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Operations Analytics; Epic: Governed Operational Reporting; Capability: Operations reports and safe exports; Feature slice: Defined report→scoped query→preview/export/schedule→evidence; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement governed reports for job/shipment aging, on-time milestones, exceptions, ePOD turnaround, actual-cost variance, profitability and billing readiness.

## 5. Business value

Provide reproducible operational evidence without ad-hoc database access or sensitive data leakage.

## 6. Source requirement

OPS-SHP/TMS/TRK/DOC/CST-004 basic slices; Brief §13; RPD-014. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168..182; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-184..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Operations Analytics schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add only approved read views/functions/indexes and report-run metadata; definitions are versioned and transactions remain authoritative.

## 14. API impact

Provide shared REST/GraphQL report definition, parameter validation, preview, async export, schedule and run-status operations.

## 15. UI/UX impact

Build accessible report catalogue/parameter/preview/run-history UI with server pagination, field policy and complete job states.

## 16. Security impact

Apply row/field/customer policy to preview/export/delivery; files are private, scanned, expiring and audited; prevent formula injection. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Use read-only queries, budgets/timeouts, PostgreSQL durable jobs for large exports, bounded retention and threshold-driven replicas.

## 18. Audit impact

Record definition/version, parameters/scope, requester, row count, sensitive columns, run/result access, schedule and expiry/deletion.

## 19. Data migration impact

Version existing report definitions and retire unsafe exports; no transaction migration.

## 20. Detailed implementation tasks

1. Define named reports, grain/parameter/column ownership and source reconciliation.
2. Implement bounded query services, preview and asynchronous export/schedule jobs.
3. Implement safe formats, formula-injection controls and private result lifecycle.
4. Build catalogue/preview/history UX and shared API contracts.
5. Verify reconciliation, access, job recovery, file security, performance and retention.

## 21. Main flow

Authorized user previews a scoped reconciled Operations report and receives a private export when requested.

## 22. Alternative flow

Scheduled report rechecks current recipient authorization and runs asynchronously.

## 23. Exception flow

Invalid/excessive range, revoked permission, job failure, unsafe cell or expired result fails safely.

## 24. Business rules

- Report definition/version and source lineage are explicit.
- Export never expands interactive access and rechecks permission at execution/download.
- Large reports are asynchronous; browser full-dataset export is forbidden.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate parameters, maximum ranges, columns, time zone/currency and definition version.
- Reconcile rows/totals to canonical permitted sources.
- Sanitize cells/filenames and enforce result expiry/retention.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Catalogue, rows, fields, schedules and recipients use entitlement/RBAC/scope/customer/field policy; sensitive exports need explicit permission. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Large/small data, hidden fields/rows, time zones, scheduled recipient revocation, job retry and malicious cell values. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Definition/parameter/query/reconciliation/export/schedule/job/idempotency tests.
- RLS/RBAC/field/record/customer/file/signed-URL/formula-injection/API/audit tests.
- Catalogue/preview/history/download E2E, accessibility, load/query-budget and dashboard regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Operations dashboard, job/file engines, all capability metrics and existing report contracts. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-183.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Reports are reproducible and reconcile to authorized data.
- Exports are private, safe, bounded and recoverable.
- No ungoverned analytics copy or browser dataset is introduced.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-018` / `OPS-184` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

