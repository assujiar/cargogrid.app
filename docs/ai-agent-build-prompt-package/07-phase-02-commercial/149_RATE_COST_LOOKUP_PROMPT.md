# Prompt 149 — Rate and Cost Lookup

**Prompt ID:** `CG-S7-COM-008`  
**Package document:** `CG-AABPP-COM-149`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-149.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-008` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Costing and Pricing; Epic: Commercial Costing; Capability: Canonical rate and cost lookup; Feature slice: Approved source discovery→validity filter→comparison→selected snapshot; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the single canonical basic vendor/service/rate and internal-cost lookup foundation consumed by Commercial and extended by Phase 6.

## 5. Business value

Provide fast, comparable, validity-aware costs without spreadsheet search or a second procurement rate model.

## 6. Source requirement

COM-OPP-001..004; PRC-RTE-001..004 basic Phase 2 slice; ASM-PK-004; CON-006; runtime ownership ADR. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-148; approved vendor/rate ownership ADR; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-150..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Costing and Pricing schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend canonical tenant-aware vendor/service/rate references, rate versions, lane/zone/mode/equipment/weight/volume breaks, components, currency, minimum/surcharge, validity, approval status and selected-rate snapshot indexes.

## 14. API impact

Provide permission-aware shared REST/GraphQL search/compare/select operations with deterministic filters, pagination, explainable matching and selected snapshot creation.

## 15. UI/UX impact

Build accessible server-side rate/cost lookup and comparison with source, validity, terms, components, warnings and restricted cost fields.

## 16. Security impact

Enforce approved/active/tenant/service scope and cost-field policy; never expose inaccessible vendor, rate or comparison candidates through counts or errors. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Use composite tenant/service/lane/validity/status indexes, bounded matching, explain plans and realistic volume budgets; no client-side full rate table.

## 18. Audit impact

Record query criteria at selection, candidates shown where policy allows, selected source/version, override reason and snapshot used by costing/quote.

## 19. Data migration impact

Adopt/migrate existing canonical rates under the ownership ADR; do not create duplicate tables or copy full vendor lifecycle data.

## 20. Detailed implementation tasks

1. Confirm ownership ADR and adopt existing vendor/service/rate contracts.
2. Implement canonical versioned rate structures and validity/approval constraints.
3. Implement indexed permission-safe search, compare, selection and snapshot semantics.
4. Build lookup/comparison UI plus shared REST/GraphQL contracts.
5. Verify matching, expiry, field security, scale, audit and Phase 6 extensibility.

## 21. Main flow

Authorized pricing user searches valid approved rates for inherited requirements, compares permitted components and selects one versioned snapshot.

## 22. Alternative flow

No standard rate fits, so an authorized ad-hoc costing response is selected with reason/approval while remaining canonical.

## 23. Exception flow

Expired/unapproved/inaccessible rate, ambiguous currency/unit, overlapping version or query-budget breach blocks selection.

## 24. Business rules

- One canonical vendor/rate foundation serves Phase 2 and Phase 6.
- Selection snapshots exact source version/criteria; later rate edits never silently reprice an issued quote.
- Full vendor onboarding, sourcing, procurement RFQ and PO stay out of Phase 2.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Match tenant, service, mode, lane/zone, equipment, cargo breaks, currency, validity and approval state.
- Detect overlapping/conflicting effective versions and invalid component/minimum/surcharge rules.
- Ad-hoc/override selection requires authority and reason.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Pricing/procurement sees permitted cost detail; sales may see availability/selected result per field policy; vendor-sensitive data and exports are restricted. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Lane/zone rates, weight/volume breaks, minimums/surcharges, expired/future/overlap/unapproved rates, ad-hoc responses and hidden vendors. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Rate version/validity/matching/component/snapshot/overlap database tests.
- Cost field/RLS/RBAC/record/cross-tenant/search-inference/API parity/audit tests.
- Lookup/compare E2E, accessibility, explain/query-budget/high-volume and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Costing requests, master data, PostGIS/location, later Procurement extension, quote snapshots and existing rates. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-149.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Lookup finds only valid authorized canonical sources with explainable matching.
- Selected cost snapshot is stable and reproducible.
- No duplicate rate domain or Phase 6 scope leakage exists.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-009` / `COM-150` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

