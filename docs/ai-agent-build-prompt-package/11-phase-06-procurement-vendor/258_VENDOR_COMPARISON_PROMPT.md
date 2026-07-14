# Prompt 258 — Vendor Comparison

**Prompt ID:** `CG-S11-PRC-009`  
**Package document:** `CG-AABPP-PRC-258`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-258.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-009` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement Execution; Epic: Commercial and Service Evaluation; Capability: Normalized Offer Comparison and Recommendation; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement exact, explainable comparison of eligible vendor rates and RFQ responses across cost, service, capacity, compliance and risk.

## 5. Business value

Enable defensible vendor selection while protecting cost data and human accountability.

## 6. Source requirement

PRC-RTE-001..004 and PRC-SRC-001..004. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..257; verified exact rate engine and assessment/compliance. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-259..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add comparison root/version, RFQ/sourcing source, normalized offers/components, currency/UOM/tax/rounding conversions, non-price criteria/weights, exclusions, score/rank, recommendation, reviewer override and selected proposal lineage.

## 14. API impact

Shared REST/GraphQL create/recalculate, include/exclude, normalize, score, explain, recommend, override-with-reason, submit and versioned read/export operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Side-by-side comparison with source/validity, normalized totals, component drilldown, non-price evidence, eligibility flags, score explanation, scenario filters and approval handoff. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Cost/budget/margin/competitor offers are strictly field-scoped; vendors cannot access comparison; exports are watermarked/audited where supported and spreadsheet-safe. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/comparison/RFQ/source/status/date; bounded offer sets, async large normalization, selective columns and target-budget comparison queries. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record response/rate/config/FX/tax/UOM versions, normalization inputs/components, criteria/weights, exclusions, score, override, reviewer and selection handoff. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Do not recreate historical comparisons from current rates; import only stored source offers/versions and label unreproducible evidence. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define offer normalization and non-price criteria/version contracts.
- Implement exact component/currency/UOM/tax/rounding comparison using canonical rate engine.
- Implement eligibility/exclusion, score/explanation, recommendation and override.
- Implement secure UI/export and approval handoff.
- Test calculation, source staleness, access, performance and selection lineage.

## 21. Main flow

System snapshots eligible RFQ responses/rates, normalizes exact commercial terms and configured non-price criteria, explains results, and an authorized user submits a selected proposal for approval.

## 22. Alternative flow

Compare scenarios by volume/fleet/date/service, select non-lowest offer with documented rationale, exclude an invalid response or request best-and-final revision.

## 23. Exception flow

Block incomparable UOM/currency/tax, expired rate/response, missing compliance/capacity, stale FX/config, manipulated export, hidden component or unexplained override. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Lowest price is not automatic selection; authorized humans own recommendation and decision.
- Every normalized total retains original offer and exact conversion/component/version lineage.
- Criteria, weights, thresholds and exclusions are configured, published and snapshotted.
- A comparison cannot rewrite the underlying vendor response/rate; revisions create a new comparison version.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate common demand basis, source/response/rate validity, exact currency/UOM/tax/rounding, eligibility, criteria weight/version and override authority. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement/pricing compare; management approves; Sales/Operations see permitted outcomes; vendors see only their own response status, never competitor data. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Lowest/non-lowest selection, mixed currencies/UOM/tiers/surcharges, missing component, excluded ineligible vendor, best-and-final, stale FX/rate and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Normalization/component/currency/UOM/tax/rounding calculation tests.
- Criteria/weight/score/explanation/version/override tests.
- Cost-field/RLS/export/competitor-confidentiality tests.
- RFQ→comparison→approval lineage and target-volume E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Rate engine, sourcing/RFQ, Finance FX/tax, Commercial costing/margin and Phase 5 capacity/eligibility. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Comparison normalization/criteria/score/exclusion/recommendation/override contract and stale/incomparable/best-final runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Invalidate only unused comparison version, preserve source offers and decisions, restore prior calculation config and reconcile downstream approvals/POs. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Offers compare on an exact common basis with source drilldown.
- Non-price criteria and exclusions are explainable/versioned.
- Human selection and override are auditable.
- Cost confidentiality and calculation regression gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-259 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

