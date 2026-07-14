# Prompt 161 — Commercial No-Reentry Enforcement

**Prompt ID:** `CG-S7-COM-020`  
**Package document:** `CG-AABPP-COM-161`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-161.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-020` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Lineage and Data Quality; Epic: Canonical Data Reuse; Capability: No re-entry of customer, contact, address, cargo, service, rate or quote; Feature slice: Cross-flow reuse rules→validation/provenance→override audit; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Enforce data reuse and provenance across the complete Commercial flow for customer, contact, address, cargo, service, rate and quote data.

## 5. Business value

Eliminate divergent manual copies while allowing explicit transaction snapshots and justified overrides.

## 6. Source requirement

CPD-018/022; Brief §6; Master Prompt Phase 2; UX no-reentry flows; all COM requirements. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-143..160; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-162..165; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Lineage and Data Quality schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend provenance/source-version metadata, canonical references, snapshot reason/type and override evidence where existing schemas lack them; avoid a duplicate generic entity store.

## 14. API impact

Apply shared validation/provenance rules at every conversion/build/handoff operation in REST and GraphQL with identical errors and override authority.

## 15. UI/UX impact

Replace repeated fields with lookup/inherit/refresh/override interactions showing source, version, staleness and reason; keep complete accessibility states.

## 16. Security impact

Canonical lookup and provenance must obey tenant/field/record scope; override cannot reveal or copy inaccessible values. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index source links/normalized lookups, bound candidates and avoid client-side master datasets; monitor repeated-entry detection without logging sensitive values.

## 18. Audit impact

Record source reference/version, snapshot creation, refresh, divergence, override actor/reason/approval and downstream propagation.

## 19. Data migration impact

Detect/reconcile brownfield duplicates and copied values through reports/queues; never mass-merge or rewrite without approved mapping and rollback.

## 20. Detailed implementation tasks

1. Catalogue each required field across lead→Job Order handoff and classify reference, governed snapshot or justified override.
2. Implement source/provenance validation and duplicate/re-entry detection at service/database boundaries.
3. Replace duplicate UI entry with inherited/linked controls and explicit override flow.
4. Create reconciliation checks for existing duplicates/divergence and downstream lineage.
5. Verify every critical flow, access, performance, audit and migration recovery.

## 21. Main flow

Each downstream record inherits/references the authorized canonical values and stores source/version provenance automatically.

## 22. Alternative flow

Authorized user creates a transaction snapshot or override because the business context legitimately differs, with reason and approval.

## 23. Exception flow

Missing/inaccessible source, stale conflicting version, duplicate target or unauthorized override blocks progression with actionable guidance.

## 24. Business rules

- No re-entry applies to customer, contact, address, cargo, service, rate and quote data.
- Snapshots are allowed only for transaction integrity and always preserve canonical source/version.
- Override is explicit, minimal, reasoned, permissioned and audited; it never silently updates the master.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Every covered downstream field must resolve to a source/version or approved override.
- Detect duplicate manual copies and inconsistent tenant/customer relationships.
- REST, GraphQL, import, job and UI paths enforce the same provenance rule.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Lookup candidates and inherited values follow current field/record scope; override and reconciliation actions require explicit permission. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Canonical/inherited/snapshotted/overridden values, stale source, inaccessible candidate, legitimate alternate delivery address, duplicate imports and two tenants. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Provenance/reference/snapshot/override/duplicate/database validation tests.
- RLS/RBAC/field/record/import/API/job/audit/cross-tenant tests.
- Full lead→accepted quote→handoff E2E, accessibility and brownfield reconciliation regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

All Prompts 143–160, import/export, master data, reports and Step 8 contract. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-161.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Covered fields are never silently retyped or copied without provenance.
- Legitimate snapshots/overrides are bounded and fully audited.
- Critical Commercial flow proves one continuous canonical lineage.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-021` / `COM-162` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

