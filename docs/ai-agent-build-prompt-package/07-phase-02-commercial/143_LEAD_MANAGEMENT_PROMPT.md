# Prompt 143 — Lead Management

**Prompt ID:** `CG-S7-COM-002`  
**Package document:** `CG-AABPP-COM-143`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-143.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-002` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Growth and Lead; Epic: Lead Acquisition; Capability: Lead capture, scoring, qualification and assignment; Feature slice: Capture→deduplicate→score→assign→qualify/disqualify lead; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a canonical tenant-aware lead lifecycle across manual, import, API, referral, campaign and integration sources with duplicate detection, governed scoring, ownership and conversion readiness.

## 5. Business value

Prevent lost or duplicate leads, shorten qualification time and establish the first trusted identity in Commercial lineage.

## 6. Source requirement

COM-LEAD-001..004; Brief §§6,7.1; UX COM-LEAD-001..002; canonical lineage and WBS task. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-142; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-144..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Growth and Lead schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend tenant-scoped lead, source, score explanation, ownership, canonical status, aging, duplicate fingerprint, optimistic version and conversion-link entities with unique/index constraints.

## 14. API impact

Expose shared-service REST/GraphQL operations for capture, search, assign, score, qualify, disqualify, merge and conversion eligibility; bulk/import paths use the Platform job framework.

## 15. UI/UX impact

Implement accessible server-paginated Lead List and Lead Detail/activity views with source, owner, aging, duplicate signals, complete states and responsive PWA behavior.

## 16. Security impact

Enforce entitlement plus own/team/department/branch/company scopes; protect bulk assignment/export and prevent cross-tenant duplicate probes. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/source/status/owner/aging/fingerprint; bound duplicate search and scoring; forbid full-browser datasets and N+1 activity queries.

## 18. Audit impact

Record source, score/rule version/explanation, owner transfers, status/reason, merge survivor, qualification and conversion linkage.

## 19. Data migration impact

Additive/backfillable lead schema; map brownfield leads and legacy statuses deterministically without merging records automatically.

## 20. Detailed implementation tasks

1. Define canonical lead identity, source taxonomy, status machine, qualification and aging rules.
2. Implement idempotent capture for UI/import/API with normalized duplicate candidates and explicit merge.
3. Implement versioned explainable scoring, assignment/transfer and SLA/reminder hooks.
4. Build list/detail/activity UI and REST/GraphQL contracts over shared services.
5. Add isolation, concurrency, import, audit, performance and conversion-readiness evidence.

## 21. Main flow

A permitted seller captures a unique lead, the system scores/assigns it, and qualification opens prospect conversion without re-entry.

## 22. Alternative flow

Import/API capture is idempotent; a duplicate candidate is linked or explicitly merged while preserving sources and activities.

## 23. Exception flow

Invalid source, duplicate conflict, stale update, unauthorized reassignment, scoring failure or missing qualification data fails safely.

## 24. Business rules

- Canonical lead state remains stable even when tenant labels differ.
- Disqualification requires a configured reason; merge preserves one survivor plus lineage.
- Automated score informs workflow but does not silently make a protected business decision.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Normalize email/phone/company identifiers before duplicate search without leaking other tenants.
- Validate allowed transition, owner scope, source, score range and required qualification fields server-side.
- Conversion can begin only from a qualified, non-merged, active lead.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Sales users see permitted own/team scopes; managers assign/transfer by policy; sensitive contact/export fields use field policy; Supreme Admin risk follows RPD-022. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Two tenants; manual/API/import/referral leads; normalized duplicates; stale versions; qualified/disqualified/merged leads; multiple owners and scopes. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Capture/idempotency/dedup/merge/status/scoring/assignment database and service tests.
- RLS/RBAC/field/record/cross-tenant, REST/GraphQL parity, import and audit tests.
- Lead List/Detail E2E, accessibility, pagination/query-budget, concurrency and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Existing auth, customer/contact masters, master data, import/export, notifications, search and Platform Core policies. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-143.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- All supported sources produce one traceable lead without silent duplication.
- Qualification, assignment, merge and access rules are deterministic, audited and tested.
- Lead is ready for prospect conversion with no customer/contact re-entry.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-003` / `COM-144` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

