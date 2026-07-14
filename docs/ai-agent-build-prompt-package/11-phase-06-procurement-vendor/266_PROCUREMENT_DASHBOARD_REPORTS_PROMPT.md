# Prompt 266 — Procurement Dashboard and Reports

**Prompt ID:** `CG-S11-PRC-017`  
**Package document:** `CG-AABPP-PRC-266`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-266.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-017` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement Analytics; Epic: Operational Visibility; Capability: Vendor Risk Rate Sourcing PO and Match Reporting; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement permission-safe, source-reconciled Procurement/Vendor dashboards and reports on live OLTP within measured budgets.

## 5. Business value

Give managers actionable visibility into vendor lifecycle, rate validity, sourcing, commitments, performance and invoice exceptions.

## 6. Source requirement

PRC-VND/ASM/RTE/SRC/POI-004, RPD-014 and the report catalogue. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..265. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-267..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add only measured report queries/views, metric definitions and optional aggregation checkpoints for vendor status/risk/compliance expiry, rate validity/competitiveness, RFQ response/cycle, capacity/acceptance, PO/contract, performance and match variance.

## 14. API impact

Shared REST/GraphQL metric definitions, filtered summary/trend/drilldown, saved views, cursor detail and asynchronous export/schedule operations with identical policy. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Procurement dashboard/work queues with KPI definitions/as-of/source, vendor risk/expiry, rate/RFQ, capacity/PO, performance and match exceptions; filters/drilldown/export and complete states. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Metrics/drilldowns/filters/sort/search/export/cache/log apply tenant/company/branch/vendor and cost/financial/customer field policy; prevent inference across vendors or tenants. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Use read-only selective live OLTP queries, tenant-aware indexes, timeouts, stable cursors, caching and explicit budgets; replicas/materialized views only after measured RPD-014 threshold. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record report/metric version, filters/as-of/source checkpoint, actor/scope, export/schedule job, row count, denial and reconciliation result without sensitive payload logging. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

No transactional migration; version metric definitions and backfill aggregation only from reconciled sources with explicit coverage/as-of. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define each metric, source, formula, grain, as-of, owner and access policy.
- Implement source-reconciled live queries/APIs and manager work queues.
- Implement responsive accessible filters/drilldown/saved views/async export.
- Measure plans/latency, add evidence-driven indexes/cache/aggregation only.
- Test metric reconciliation, inference/isolation, pagination, export and target volume.

## 21. Main flow

Authorized manager opens as-of metrics and queues, applies scoped filters, drills to source records under the same policy, and requests bounded audited export when needed.

## 22. Alternative flow

Saved view, scheduled report, CSV/XLSX/PDF export, service/category/branch comparison or degraded cached view with visible freshness.

## 23. Exception flow

Block unscoped aggregate, restricted drilldown/export, unsafe filter/sort, stale/unreconciled metric, query timeout, job failure or inference-risk request. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Every KPI has a versioned definition, canonical source, grain, as-of/freshness and reconciliation equation.
- Dashboard reads live OLTP by default under RPD-014 guards; no automatic warehouse/materialized architecture.
- Summary, drilldown, search, export and cache enforce identical record/field policy.
- No dashboard may present partial/stale data as current or auto-decide vendor lifecycle.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate metric/filter/date/grain definitions, source checkpoint, user scope, field policy, cursor/sort limits, export size and freshness/reconciliation. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement staff view operational scope; managers see approved cross-team metrics/cost; Finance/Operations see their permitted reports; vendor portal only own explicitly approved score/status. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Empty/large datasets, multiple branches/services/vendors, expiring docs/rates, RFQ/no-response, PO/match exceptions, restricted costs, stale cache and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Metric formula/source/as-of/reconciliation tests.
- RLS/RBAC/field/inference/filter/sort/search/export/cache tests.
- Cursor/query plan/budget/cache/async export/load tests.
- Dashboard drilldown/accessibility/browser and degraded-state E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Vendor lifecycle/compliance/rates/sourcing/RFQ/PO/performance/match source modules, Platform reports/jobs and Finance/Operations dashboards. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Metric/source/formula/grain/as-of/access/query-budget/export contract and timeout/stale/reconciliation/support runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Disable affected metric/query/export, preserve source transactions, restore last verified definition/cache and reconcile before republishing. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Required Procurement/Vendor metrics reconcile to canonical sources.
- All views/drilldowns/exports enforce identical policy.
- Live OLTP budgets and bounded degraded behavior pass.
- No unsupported production or predictive claim is made.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-267 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

