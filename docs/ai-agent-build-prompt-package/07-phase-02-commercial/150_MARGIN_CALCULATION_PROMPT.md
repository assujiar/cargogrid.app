# Prompt 150 — Margin Calculation

**Prompt ID:** `CG-S7-COM-009`  
**Package document:** `CG-AABPP-COM-150`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-150.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-009` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Costing and Pricing; Epic: Commercial Pricing; Capability: Deterministic margin calculation; Feature slice: Cost snapshot + selling inputs→margin/markup/discount→threshold decision; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement exact, versioned and explainable quotation margin calculations with component totals, discount, minimum-margin thresholds and governed overrides.

## 5. Business value

Protect commercial profitability and approval integrity while giving authorized users a reproducible price explanation.

## 6. Source requirement

COM-QTN-001..004; COM-CPR-001..004; Brief §7.1 Quotation; financial integrity guardrails. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-149; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-151..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Costing and Pricing schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend versioned margin-rule/config references, exact decimal cost/sell/discount/tax/FX inputs, rounding policy, calculated result, threshold outcome and override evidence.

## 14. API impact

Provide one shared calculation service used by REST/GraphQL/UI/jobs; accept typed inputs/version and return deterministic totals, margin, markup, warnings and approval requirement.

## 15. UI/UX impact

Build permission-aware pricing summary with component breakdown, margin/markup/discount, warnings and recalculation reason; never compute authoritative money only in browser.

## 16. Security impact

Restrict cost, margin, discount and override fields/actions; redacted API projections and exports must match field policy. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Bound component count and rule lookup; cache published immutable rules safely and benchmark batch quote recalculation.

## 18. Audit impact

Record every material input/source version, formula/rule/rounding/FX version, output, threshold, override actor/reason and recalculation.

## 19. Data migration impact

Backfill calculations only when historical inputs/rules are provable; otherwise preserve legacy totals with explicit unverifiable status.

## 20. Detailed implementation tasks

1. Define exact money, component, margin/markup, discount, tax/FX and rounding semantics.
2. Implement one deterministic versioned server calculation service.
3. Implement threshold outcomes and governed override/approval handoff.
4. Build permission-aware pricing explanation UI/API contracts.
5. Prove precision, reproducibility, field security, concurrency and migration behavior.

## 21. Main flow

Selected cost snapshots and selling inputs calculate exact totals and margin; passing result is ready for quotation.

## 22. Alternative flow

Below-threshold result creates an approval requirement or authorized reasoned override without changing source cost.

## 23. Exception flow

Mixed/unknown currency, missing FX, negative/overflow value, stale rule or unauthorized discount/override fails closed.

## 24. Business rules

- Money never uses binary floating point; currency and rounding are explicit.
- Margin and markup are distinct named formulas and cannot be interchanged.
- Issued quote pins calculation inputs and rule versions; configuration changes do not silently reprice it.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Validate component signs, scale, currency, FX source/date, discount bounds and total reconciliation.
- Recompute server-side and reject client-total mismatch.
- Threshold/override outcome must match published effective rule and access policy.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Only permitted pricing/manager roles see cost/margin; sales/customer projections expose selling values only as authorized. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Zero/negative/large values, multi-component/minimum/surcharge, rounding edges, below-threshold discount, mixed currency/FX and concurrent rule publish. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Decimal/formula/rounding/component/FX/rule-version/recalculation unit and property tests.
- Field/RBAC/record/API projection/audit/concurrency/database precision tests.
- Pricing explanation E2E, accessibility, batch performance and quote regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Rate snapshots, costing totals, approval engine, quote builder, reports and finance-boundary money types. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-150.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Calculation is exact, reproducible and identical across service/API/UI.
- Threshold and override behavior is policy-driven and audited.
- Unauthorized users cannot infer cost or margin.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-010` / `COM-151` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

