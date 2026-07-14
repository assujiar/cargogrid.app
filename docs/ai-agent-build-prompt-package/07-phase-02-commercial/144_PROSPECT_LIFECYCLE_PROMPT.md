# Prompt 144 — Prospect Lifecycle

**Prompt ID:** `CG-S7-COM-003`  
**Package document:** `CG-AABPP-COM-144`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-144.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-003` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Growth and Lead; Epic: Qualification Conversion; Capability: Prospect lifecycle; Feature slice: Qualified lead→prospect→customer candidate; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement prospect as a governed pre-customer commercial identity that preserves qualified-lead lineage, duplicate candidates and conversion eligibility.

## 5. Business value

Let sales progress qualified organizations without prematurely creating conflicting customer masters.

## 6. Source requirement

COM-LEAD-001..004; COM-CRM-001..004; Brief §§6,7.1; Master Prompt Phase 2. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-143; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-145..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Growth and Lead schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend tenant-scoped prospect identity, lead links, organization/contact snapshots, status, owner, qualification version, duplicate candidate and conversion outcome constraints.

## 14. API impact

Provide idempotent lead-to-prospect, prospect maintenance, duplicate review, disqualify/archive and customer-conversion eligibility operations through shared REST/GraphQL services.

## 15. UI/UX impact

Build accessible prospect queue/detail/conversion preview with mapped fields, duplicate candidates, lineage and complete loading/empty/error/conflict states.

## 16. Security impact

Enforce lead/prospect owner/team/hierarchy scopes and field policy for personal/contact data; duplicate search cannot expose inaccessible accounts. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/status/owner/normalized identity and conversion link; bound duplicate candidates and server-paginate queues.

## 18. Audit impact

Record lead source link, mapped fields, qualification snapshot, status, owner, duplicate decision and conversion attempts/outcomes.

## 19. Data migration impact

Backfill only verified prospect records; preserve legacy lead/customer links and route ambiguity to a reconciliation queue.

## 20. Detailed implementation tasks

1. Define prospect identity, lifecycle and difference from lead/account/customer.
2. Implement idempotent qualified-lead conversion with source link and mapped-field preview.
3. Implement duplicate candidate/link/merge decision without silent customer creation.
4. Build prospect queue/detail/conversion UX and API contracts.
5. Verify no-reentry, access, concurrency, audit, rollback and downstream readiness.

## 21. Main flow

A qualified lead converts once to a prospect, preserving owner, contact context, requirements and source lineage.

## 22. Alternative flow

An authorized user links the lead to an existing accessible prospect/account after reviewing duplicate evidence.

## 23. Exception flow

Unqualified/merged lead, conflicting identity, concurrent conversion or inaccessible existing account blocks conversion.

## 24. Business rules

- One conversion idempotency key yields one prospect outcome.
- Prospect is not a customer until approved conversion rules pass.
- Source lead remains linked and is never silently deleted or rewritten.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Lead must be qualified and eligible at the same version used for conversion.
- Normalized legal/trade/contact identifiers drive scoped duplicate checks.
- Prospect-to-customer readiness requires mandatory legal, billing, service and credit inputs configured for the tenant.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Sales own/team scopes apply; manager approval may be configured; customer legal/credit fields remain field-restricted. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Qualified/unqualified/merged leads, duplicate existing prospects/accounts, concurrent conversion, incomplete legal data and two-tenant negative cases. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Conversion idempotency, uniqueness, mapping, lifecycle and concurrency tests.
- Scoped duplicate, RLS/RBAC/field/record, audit and REST/GraphQL contract tests.
- Prospect queue/detail/conversion E2E, accessibility and no-reentry regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Lead state, existing customers/accounts/contacts, duplicate service, jobs and downstream references. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-144.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Qualified lead converts exactly once with complete lineage.
- Duplicate handling never leaks or silently forks customer identity.
- Prospect remains conversion-ready without retyping source data.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-004` / `COM-145` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

