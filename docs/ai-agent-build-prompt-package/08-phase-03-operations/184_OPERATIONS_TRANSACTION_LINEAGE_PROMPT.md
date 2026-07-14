# Prompt 184 — Operations Transaction Lineage

**Prompt ID:** `CG-S8-OPS-018`  
**Package document:** `CG-AABPP-OPS-184`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-184.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-018` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Lineage and Completion; Epic: Quote-to-Billing Evidence; Capability: Approved quote to shipment to ePOD to billing-readiness lineage; Feature slice: Commercial source manifest→Job→Shipment/events/evidence/cost→readiness manifest; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Enforce complete canonical lineage and no-reentry from approved quotation through Job Order, Shipment, milestones, ePOD, cost/profitability and billing readiness.

## 5. Business value

Give Finance, customers and auditors one traceable operational transaction chain.

## 6. Source requirement

OPS-SHP/TRK/DOC/CST-001..004 basic slices; CPD-018/022; Master Prompt critical E2E. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168..183; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-185..188; Step 9 Finance; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Lineage and Completion schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend lineage edges/manifests, stable source/target IDs, version/hash, relation type, override/provenance metadata and orphan/duplicate reconciliation checks where missing.

## 14. API impact

Expose permission-aware shared REST/GraphQL/internal lineage traversal and readiness handoff references without copying domain payloads.

## 15. UI/UX impact

Build scoped lineage panel on job/shipment/readiness views showing source/downstream links, status and recoverable gaps without sensitive-field leakage.

## 16. Security impact

Lineage traversal applies every target record/field/customer policy; existence/count/errors cannot reveal inaccessible records. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/source/target/relation/version; bound traversal depth/breadth and prohibit unbounded graph queries.

## 18. Audit impact

Record lineage creation/correction, source versions/hashes, override/provenance, orphan reconciliation and privileged traversal.

## 19. Data migration impact

Detect orphan/duplicate/divergent brownfield chains and reconcile through reviewed mappings; never fabricate source links.

## 20. Detailed implementation tasks

1. Catalogue required lineage edges and source/version fields across the full Phase 3 flow.
2. Implement atomic lineage creation at each domain transition and no-reentry validations.
3. Implement bounded scoped traversal, orphan/duplicate checks and Finance readiness manifest.
4. Build lineage panels and reconciliation outputs.
5. Verify completeness, access, idempotency, migration and critical E2E.

## 21. Main flow

One accepted quote chain resolves through Job, Shipment, milestone/ePOD/cost to one billing-readiness evidence manifest.

## 22. Alternative flow

Authorized correction adds a reasoned lineage mapping/override without deleting prior evidence.

## 23. Exception flow

Missing/orphan/duplicate/cross-tenant edge, inaccessible target, source hash mismatch or cycle blocks readiness/closure.

## 24. Business rules

- Customer, contact, address, cargo, service, rate, quote and price are referenced or governed snapshots with provenance.
- Every transition is idempotent and cannot create a duplicate target outcome.
- Billing readiness manifest references Operations evidence; it does not copy or post Finance transactions.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Every required edge has matching tenant, canonical IDs, relation, source version/hash and valid lifecycle.
- Detect cycles, orphans, duplicate outcomes and silent copied values.
- Traversal output is filtered per record/field/customer policy at every hop.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Internal roles traverse only authorized records; customer/public sees a purpose-limited sanitized timeline, not the internal lineage graph. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Complete/missing/orphan/duplicate/cycle/mismatched chains, overrides, hidden financial/vendor records and two tenants/customers. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Lineage edge/manifest/idempotency/orphan/cycle/hash/database tests.
- RLS/RBAC/field/record/customer/cross-tenant/API traversal/audit tests.
- Full accepted quote→billing readiness E2E, lineage panel, performance and migration regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Commercial JobOrderDraftInput, all Operations capabilities and Step 9 Finance readiness contract. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-184.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Critical flow has complete source/version lineage with no silent re-entry.
- Duplicate/orphan/cross-tenant chains are detected and block safely.
- Finance receives one stable readiness evidence manifest.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-019` / `OPS-185` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

