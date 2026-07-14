# Prompt 155 — Customer and Account Conversion

**Prompt ID:** `CG-S7-COM-014`  
**Package document:** `CG-AABPP-COM-155`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-155.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-014` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Customer and Contract; Epic: Commercial Master Conversion; Capability: Prospect/account/customer conversion; Feature slice: Accepted commercial identity→canonical customer/account/contact/site; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement idempotent conversion from accepted prospect/account context to the canonical customer/account master while reusing contacts, addresses, sites and requirements.

## 5. Business value

Open downstream operations and finance readiness without duplicate customer masters or manual re-keying.

## 6. Source requirement

COM-LEAD-001..004; COM-CRM-001..004; COM-QTN-001..004; Brief §6/customer dictionary. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-144..146, COM-154; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-156..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Customer and Contract schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend conversion record, stable source/target links, customer/account/legal/billing/service status, contact/address/site relationships, duplicate decision and idempotency constraints against canonical masters.

## 14. API impact

Provide shared REST/GraphQL conversion preview, validate, execute, retry/reconcile and existing-customer-link operations.

## 15. UI/UX impact

Build accessible conversion preview/mapping/duplicate review showing inherited fields, missing requirements, target links and complete conflict states.

## 16. Security impact

Restrict legal/tax/billing/credit fields and customer creation authority; duplicate candidates are filtered by tenant/organizational access. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index normalized legal/tax/trade/contact/site identities and source/target links; bound duplicate search and conversion transaction.

## 18. Audit impact

Record source lead/prospect/account/quote/acceptance versions, field mappings, duplicate decision, created/linked entities and retry/reconciliation.

## 19. Data migration impact

Adopt existing customer links; ambiguous legacy conversions enter a reconciliation queue without creating new masters.

## 20. Detailed implementation tasks

1. Define canonical account/customer distinction, required master fields and conversion policy.
2. Implement preview/mapping and scoped duplicate candidates over source data.
3. Implement atomic idempotent create-or-link of customer/account/contact/address/site relationships.
4. Build conversion UX and shared API contracts with reconciliation.
5. Verify no-reentry, legal/field access, concurrency, audit and downstream readiness.

## 21. Main flow

Authorized user reviews inherited accepted data and atomically links or creates one canonical customer/account with reused contacts/sites.

## 22. Alternative flow

Source is linked to an existing accessible customer after reviewed duplicate evidence and mapping.

## 23. Exception flow

Conflicting legal/tax identity, inaccessible duplicate, missing mandatory billing/service data or concurrent conversion blocks safely.

## 24. Business rules

- Conversion never silently duplicates customer, contact, address or site.
- Source Commercial records remain linked and immutable for normal roles after conversion.
- Customer status and credit readiness are distinct; conversion does not grant credit automatically.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Validate accepted quote context and configured legal/billing/service/customer fields.
- Enforce normalized identity uniqueness and idempotent source-to-target mapping.
- Every copied snapshot/reused reference states provenance and target ownership.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Authorized commercial/admin roles convert; legal/tax/billing/credit and duplicates use field/record scope; customer users gain no access automatically. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

New/existing customers, duplicate legal/tax/contact/site, parent/subsidiary, incomplete billing data, concurrent retry and cross-scope candidate. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Conversion/idempotency/uniqueness/mapping/relationship/transaction tests.
- RLS/RBAC/field/record/duplicate-inference/API parity/audit tests.
- Preview/map/convert/reconcile E2E, accessibility and no-reentry regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Lead/prospect/account/contact, accepted quote, master data, later Finance/Portal and customer references. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-155.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- One source context yields one canonical customer/account outcome.
- Contacts, addresses, sites and requirements are reused with provenance.
- No unauthorized duplicate disclosure or implicit credit grant occurs.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-015` / `COM-156` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

