# Prompt 152 — Quotation Versioning

**Prompt ID:** `CG-S7-COM-011`  
**Package document:** `CG-AABPP-COM-152`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-152.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-011` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Quotation Lifecycle; Epic: Customer Offer; Capability: Quotation revision and version integrity; Feature slice: Draft/issued quote→new immutable normal-role version→supersession; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement quotation version creation, supersession, comparison and locking so issued/accepted commercial terms remain reproducible.

## 5. Business value

Allow controlled negotiation without overwriting what was previously approved or sent.

## 6. Source requirement

COM-QTN-001..004; Brief §7.1 Quotation; configuration/version guardrails. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-151; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-153..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Quotation Lifecycle schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend monotonically versioned quote revisions, parent/root identity, status, source/calculation/template snapshots, supersession link, change reason and normal-role lock constraints.

## 14. API impact

Provide shared REST/GraphQL create-revision, compare, list, restore-as-new-draft and supersede operations with optimistic concurrency.

## 15. UI/UX impact

Build accessible version history, compare and revise actions showing material changes, status and accepted/superseded locks.

## 16. Security impact

Restrict revise/compare sensitive lines and prevent normal-role mutation of issued/accepted versions; disclose RPD-022 Supreme Admin exception. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/root/version/status; generate bounded comparisons and avoid loading every document/line version by default.

## 18. Audit impact

Record revision actor/reason, copied source versions, material diff, issue/send/accept/supersede events and any Supreme mutation.

## 19. Data migration impact

Map legacy quote revisions to root/version ordering only with deterministic evidence; ambiguous order stays quarantined for reconciliation.

## 20. Detailed implementation tasks

1. Define quote root/version/state/lock and supersession invariants.
2. Implement atomic next-version creation and snapshot copying with concurrency protection.
3. Implement material diff, history and restore-as-new-draft behavior.
4. Build version history/compare/revise UX and API contracts.
5. Verify locks, RPD-022 disclosure, documents, audit and downstream references.

## 21. Main flow

Authorized user creates a new draft revision from the latest eligible quote; prior issued version stays unchanged and traceable.

## 22. Alternative flow

An older version is restored as a new latest draft with explicit source and reason.

## 23. Exception flow

Concurrent next-version request, accepted lock, invalid predecessor or inconsistent snapshot fails without partial revision.

## 24. Business rules

- Normal roles never edit issued/accepted versions; revisions create new versions.
- Only one version can hold each mutually exclusive active/accepted state under configured rules.
- RPD-022 permits Supreme mutation/deletion, so tamper-proof claims are forbidden.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Version sequence/root uniqueness and transition are database-enforced.
- Every version pins calculation, customer/contact/address/service/rate/terms/template source versions.
- Compare output reconciles all material customer-facing and restricted changes.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Sales revises eligible drafts; approval roles view sensitive diff by permission; customer access is limited to sent versions. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Multiple drafts/issued/superseded/accepted versions, concurrent revision, restore older version, restricted margin diff and Supreme exception. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Version sequence/root/lock/supersession/concurrency/snapshot database tests.
- RLS/RBAC/field/record/API parity/document/audit/RPD-022 disclosure tests.
- History/compare/revise E2E, accessibility and quotation regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Quote numbering, documents, approval/acceptance links, reports and Job Order snapshot references. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-152.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Every revision is unique, ordered and fully reproducible.
- Prior issued/accepted evidence remains protected for normal roles.
- Version comparison respects access and reconciles material change.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-012` / `COM-153` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

