# Prompt 264 — Vendor Performance

**Prompt ID:** `CG-S11-PRC-015`  
**Package document:** `CG-AABPP-PRC-264`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-264.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-015` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Vendor Governance; Epic: Performance and Risk; Capability: Vendor KPI Scorecard Issue and Lifecycle Action; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement source-reconciled vendor performance metrics, scorecards, issues and governed lifecycle actions.

## 5. Business value

Continuously evaluate vendor reliability, service quality, cost competitiveness and compliance using explainable evidence.

## 6. Source requirement

PRC-POI-001..004, PRC-ASM-001..004 and Product Brief Vendor Performance KPI catalogue. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..263; verified Operations, claim, compliance, sourcing and Finance evidence. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-265..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add KPI definition/version, measurement window, source events, exclusions, targets/weights, metric values, scorecard/band, issue/corrective action, review/approval, manual adjustment and vendor suspension/blacklist/reactivation recommendation lineage.

## 14. API impact

Shared REST/GraphQL definition-read, calculate/recalculate, scorecard/list/drilldown, issue/corrective-action, review/adjust-with-reason and governed lifecycle-recommendation operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Vendor scorecard with on-time pickup/delivery, acceptance, response, capacity fulfillment, compliance, claims/damage, competitiveness, rate validity, invoice accuracy, service/complaint/SLA metrics; source drilldown and issue/action timeline. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Field-policy limits cost, customer complaint, claim, finance and sensitive evidence; vendor sees only allowed own score/detail and cannot change source metrics or lifecycle decision. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor/window/metric/status/service; async bounded calculation, incremental source checkpoints, cursor scorecards and materialized view only after measured RPD-014 threshold. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record metric/formula/config/source checkpoint, included/excluded events, score/weight/band, adjustment reason/approver, issue/action and downstream eligibility/lifecycle decision. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Do not back-calculate official historical scores without complete source evidence; label partial coverage and establish first trustworthy window. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define KPI catalogue/formulas/windows/targets/weights/exclusions and source ownership.
- Implement source ingestion/reconciliation and repeatable score calculation.
- Implement scorecard/drilldown, issue/corrective-action and manual adjustment controls.
- Integrate governed suspension/blacklist/reactivation and sourcing eligibility.
- Test formulas, late events, access, performance, migration and decision lineage.

## 21. Main flow

A scheduled/on-demand job reads versioned operational/compliance/sourcing/claim/Finance sources, calculates explainable metrics for a window, publishes a reviewed scorecard and opens governed corrective/lifecycle actions.

## 22. Alternative flow

Category/service-specific scorecard, provisional partial-data view, dispute a source event, adjust with approval or trigger reassessment.

## 23. Exception flow

Block unreconciled sources, insufficient coverage, duplicate/late event, formula/config mismatch, unsafe customer detail, unauthorized adjustment or automated blacklist. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Metrics cite canonical sources and reconciliation checkpoints; scorecard is not free-form manual truth.
- Formula, window, target, exclusion, weight and band are versioned and snapshotted.
- System may recommend; authorized humans decide suspension, blacklist and reactivation.
- Late/corrected source events trigger governed recalculation/version, never silent historical rewrite.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate vendor/source/window completeness, event uniqueness, metric formula/config version, exact units/rounding, review/adjustment authority and lifecycle prerequisites. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement managers review; analysts calculate/drill down permitted sources; vendor may view/dispute allowed own metrics; Operations/Finance/customer data remains field-scoped. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Good/poor/new vendor, sparse data, late/corrected event, multi-service scorecards, manual adjustment, complaint/claim, blacklist/reactivation and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- KPI formula/window/exclusion/weight/rounding/reconciliation tests.
- Late event/recalculation/version/adjustment/review tests.
- RLS/field/vendor/customer/Finance drilldown isolation tests.
- Performance→corrective action→eligibility/lifecycle E2E and target-volume job tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Shipment milestones/ePOD/claims, capacity/acceptance, compliance, invoice matching/Finance and sourcing eligibility. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

KPI source/formula/window/score/band/adjustment/dispute/lifecycle contract and recalculation/data-gap/corrective-action runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Pause score publication/actions, preserve source/checkpoints, restore prior formula version and recalculate affected windows before eligibility resumes. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Scorecards reconcile to canonical sources with explainable formulas.
- All required vendor KPI categories are covered or explicitly not applicable.
- Adjustments and lifecycle actions are human-governed.
- Field isolation and target-volume calculation pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-265 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

