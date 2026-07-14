# Prompt 255 — Vendor Rate and Pricelist

**Prompt ID:** `CG-S11-PRC-006`  
**Package document:** `CG-AABPP-PRC-255`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-255.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-006` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Procurement Pricing; Epic: Rate Governance; Capability: Quotation, Rate Card and Pricelist; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Extend the canonical Phase 2 vendor-rate foundation into complete versioned quotations, rate cards and pricelists with exact validity and calculation semantics.

## 5. Business value

Give Commercial, Operations and Procurement one trustworthy vendor-cost source.

## 6. Source requirement

PRC-RTE-001..004 and Product Brief Vendor Quotation and Pricelist capabilities. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..254; verified Phase 2 rate ownership, Finance currency/tax and Platform master/config. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-256..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Extend canonical vendor rate with quotation/pricelist/version, service/mode, origin/destination/zone/distance, fleet/container, weight/volume/UOM tiers, currency/tax, surcharge/accessorial, minimum charge, validity, lead time, capacity terms, approval and source/config snapshots.

## 14. API impact

Shared REST/GraphQL draft/import/validate/compare-read, submit/approve/publish/supersede/expire and exact calculate/lookup operations using one rate engine. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Rate/pricelist directory, structured editor/tier grid, import validation, duplicate/overlap warnings, calculation preview, approval/version timeline and validity alerts. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Vendor cost/rate is cost-sensitive; apply view-cost/approve/export field policy and prevent customer exposure, unsafe formulas and spreadsheet injection. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor/service/mode/origin/destination/zone/fleet/status/validity; selective lookup, cursor tables, async import and measured search plans. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record source quotation/file, rate/version/config, inputs/UOM/conversion, component/tier/minimum/tax/currency/rounding, approval, publish/supersede and every downstream snapshot. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Adopt Phase 2 rates, classify unknown semantics, detect overlaps and preserve existing costing/shipment snapshots; never silently reinterpret tiers. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Reconcile and extend the Phase 2 canonical rate schema/engine.
- Define all dimensions, components, UOM/currency/tax/rounding and overlap rules.
- Implement structured editor/import, exact lookup/calculate APIs and approval/publish lifecycle.
- Add validity/expiry/supersession and downstream snapshot compatibility.
- Run calculation, ambiguity, scope, import, performance and migration tests.

## 21. Main flow

Procurement captures or imports a vendor quotation, resolves dimensions/components, validates exact calculation and overlap, submits for approval and publishes a version used by costing/sourcing/assignment via immutable snapshot.

## 22. Alternative flow

Create lane/service/fleet/zone/distance/container/tier rate, ad-hoc quotation with expiry, scheduled future version or approved surcharge amendment.

## 23. Exception flow

Block ambiguous overlap, missing UOM/currency/tax source, invalid tier/validity, duplicate import, self-approval, expired vendor/compliance or stale version. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- One canonical rate engine/store serves Commercial, Procurement and Operations; no duplicate rate truth.
- Every calculation snapshots vendor/rate/config/source version, exact inputs, UOM conversion, components, currency/tax and rounding.
- Active transactions retain their applied version under RPD-040; reprice is explicit.
- Rate recommendation/selection remains human-governed; customer users never see vendor cost.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate active approved vendor, service/coverage, dimensions, ordered non-overlapping tiers, exact decimals/UOM, currency/tax sources, validity and lifecycle/version. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement/pricing edit; designated approvers publish; Sales/Operations use scoped lookup; Finance reads source; customer/vendor portal fields are restricted by policy. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

All rate bases, tiers/minimum/surcharges, multi-currency, future/expired/overlap, ad-hoc quote, import errors, rounding edges and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Exact component/tier/minimum/UOM/currency/tax/rounding tests.
- Overlap/validity/version/approval/supersession/snapshot tests.
- RLS/RBAC/field/export/customer leakage and import tests.
- Commercial lookup, sourcing, assignment and invoice-match compatibility/load tests.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Phase 2 costing/margin/quotation, Phase 3/5 assignment/actual cost, Finance source lineage and rate search/import. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Canonical rate dimensions/calculation/version/validity/approval/snapshot contract and import/overlap/reprice/expiry runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Unpublish only unused eligible version, preserve used snapshots, restore last compatible lookup and reconcile affected costing/assignment/PO/match records. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- One exact canonical vendor-rate source serves all consumers.
- Rates support required dimensions, tiering, components and validity.
- Approval, snapshot and RPD-040 behavior are proven.
- Cost-field isolation and target lookup budgets pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-256 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

