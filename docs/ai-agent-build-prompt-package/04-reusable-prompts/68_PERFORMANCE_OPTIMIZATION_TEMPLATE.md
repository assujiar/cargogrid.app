# Template 68 — Performance Optimization

**Prompt ID:** `CG-S4-REUSE-016`  
**Package document:** `CG-AABPP-REUSE-068`  
**Version:** `0.5.0`  
**Intended use:** Correct one measured performance bottleneck without changing business semantics.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Performance and Scalability.

## 4. Objective

Improve {{MEASURED_BOTTLENECK}} from {{BASELINE}} to the approved budget while preserving results, access and contracts.

## 5. Business value

Keep critical CargoGrid flows responsive and scalable without speculative optimization.

## 6. Source requirement

{{PERFORMANCE_REQUIREMENT_IDS}}, {{BASELINE_EVIDENCE_ID}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Use measured query plans/cardinality; tenant-aware indexes/query rewrites/pagination require migration and data-preservation evidence.

## 14. API impact

Preserve response semantics while bounding query count, payload, complexity, pagination and timeouts.

## 15. UI/UX impact

Improve loading/interaction/bundle/render without hiding stale/partial/error states or loading all data client-side.

## 16. Security impact

Caching/batching/index/read-model changes must retain tenant/field/record authorization and prevent inference.

## 17. Performance impact

Primary scope: define workload/environment/dataset/concurrency, measure p50/p95/p99 or relevant budget before/after and under failure.

## 18. Audit impact

Optimization must preserve audit events/order/correlation and measurement evidence.

## 19. Data migration impact

Read-model/materialization/backfill is separate, idempotent, freshness-governed and reconciled.

## 20. Detailed implementation tasks

1. Reproduce bottleneck in a safe representative environment and profile root cause.
2. Choose the smallest evidence-backed optimization; reject speculative unrelated tuning.
3. Implement with correctness/access/compatibility safeguards and invalidate caches correctly.
4. Run before/after/cold/warm/concurrent/failure measurements and regression checks.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Representative authorized workload returns identical correct result within budget.

## 22. Alternative flow

Cold cache, alternate filter/page/tenant distribution and supported device remain bounded.

## 23. Exception flow

Timeout, cancellation, dependency slowdown, cache miss/stale state and overload degrade safely.

## 24. Business rules

- Slow screen/query is a defect; improvement cannot trade correctness, freshness or access.
- No SELECT *, full-browser dataset, N+1 or unapproved realtime.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Datasets, environment, commands and statistics are comparable and reproducible.
- Result counts/content/ordering and authorization are identical before/after.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Test cache keys, batches, read models and exports for tenant/field/record isolation.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Representative sizes/skew/tenants, hot/cold cache, common/worst filters, concurrency and failure injection. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Correctness/query count/plan, benchmark/load, API/UI render/bundle and cancellation tests.
- Cross-tenant/cache leakage, regression and resource utilization tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Business results, audit, API contracts, migrations, jobs, reports and critical E2E under load.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Approved budget passes with reproducible before/after evidence.
- No correctness, security, freshness, resource or adjacent performance regression.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
