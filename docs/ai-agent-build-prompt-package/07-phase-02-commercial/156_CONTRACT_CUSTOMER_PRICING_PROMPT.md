# Prompt 156 — Contract and Customer Pricing

**Prompt ID:** `CG-S7-COM-015`  
**Package document:** `CG-AABPP-COM-156`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-156.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-015` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Customer and Contract; Epic: Commercial Agreement; Capability: Contract and customer pricing lifecycle; Feature slice: Accepted quote→contract/pricelist version→effective customer rate; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned customer contracts and pricing derived from accepted quotations with effective dates, service/lane conditions and reproducible rate selection.

## 5. Business value

Turn negotiated terms into governed reusable customer pricing without overwriting quote or future Operations/Finance rules.

## 6. Source requirement

COM-QTN-001..004; COM-CPR-001..004; Brief §§6,11; customer data dictionary. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-150, COM-154..155; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-157..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Customer and Contract schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend tenant/customer-scoped contract, pricelist, version, service/lane/rate/component, minimum/surcharge/discount, currency, validity, approval/publish state and accepted-quote source constraints.

## 14. API impact

Provide shared REST/GraphQL draft/version/compare/submit/publish/retire/search-effective-pricing operations using exact money and access services.

## 15. UI/UX impact

Build accessible contract/pricelist list, detail, version comparison and effective-rate workbench with warnings and complete states.

## 16. Security impact

Restrict selling, discount, margin and contract documents through field/record policy; customer visibility is explicit and scoped. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/customer/service/lane/status/effective dates; bound effective-price resolution and version comparisons.

## 18. Audit impact

Record accepted quote source, version changes, price components, approval/publish/retire, effective selection and overrides.

## 19. Data migration impact

Map legacy contracts/pricelists only with customer, validity, currency, service and source reconciliation; never silently activate ambiguous rates.

## 20. Detailed implementation tasks

1. Define contract/pricelist/version/effective-date and quote-source invariants.
2. Implement draft/version/approval/publish/retire lifecycle over exact pricing components.
3. Implement deterministic effective customer-price lookup and snapshot.
4. Build management/compare/lookup UX plus shared REST/GraphQL contracts.
5. Verify overlap, access, calculation, audit and downstream consumption boundary.

## 21. Main flow

Accepted quote creates a draft contract/pricelist version; after governed approval/publish it resolves as the effective customer price.

## 22. Alternative flow

Renewal/amendment creates a future-dated version while current transactions retain pinned prior pricing.

## 23. Exception flow

Overlapping active version, stale acceptance, invalid currency/component, unauthorized discount or expired contract blocks publish/use.

## 24. Business rules

- Accepted quote remains source evidence; contract changes create versions rather than rewriting it.
- Active critical transactions retain applied pricing version unless explicit reprice/migration runs.
- Customer pricing is selling-side; vendor cost remains separately permissioned and sourced.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Validate customer/service/lane/component/currency, dates, overlaps, minimum/surcharge/discount and approval state.
- Effective lookup returns one deterministic eligible version or fails explicitly.
- Published totals reconcile to exact calculation and accepted customer terms.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Commercial managers administer by scope; sales reads permitted selling terms; customers see only published own terms when enabled. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Current/future/expired/overlapping contracts, amendments, multiple services/lanes/currencies, restricted discounts and accepted-quote sources. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Version/effective/overlap/publish/lookup/component/database tests.
- RLS/RBAC/field/record/API parity/document/audit tests.
- Contract/pricelist/compare/lookup E2E, accessibility, performance and quote regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Accepted quotes, customer master, margin, approval/config engines, future Job Order pricing snapshots and reports. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-156.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Contract pricing is versioned, effective-dated and traceable to acceptance.
- One deterministic authorized price resolves for a valid context.
- No issued quote or active transaction is silently repriced.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-016` / `COM-157` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

