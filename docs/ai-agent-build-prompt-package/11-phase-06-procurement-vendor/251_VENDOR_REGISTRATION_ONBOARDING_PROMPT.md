# Prompt 251 — Vendor Registration and Onboarding

**Prompt ID:** `CG-S11-PRC-002`  
**Package document:** `CG-AABPP-PRC-251`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-251.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-002` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Vendor Governance; Epic: Canonical Vendor Lifecycle; Capability: Registration, Self-Registration and Onboarding; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the canonical tenant-scoped vendor profile and governed onboarding lifecycle without duplicating the Phase 2 vendor/rate foundation.

## 5. Business value

Create reusable, verified vendor data once so Commercial, Operations, Procurement and Finance can transact without re-entry.

## 6. Source requirement

PRC-VND-001..004, PRC-VND-US-001, BP-A08 and the Product Brief Vendor Registration capability. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-250; verified Phase 2 vendor/service/rate ownership and Platform identity/document/approval foundations. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-252..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Extend canonical vendor with legal identity, category, contacts/addresses, services, coverage, owned-resource references, payment-term reference, intake source, duplicate-review lineage and canonical Draft→Submitted→Review→Approved→Active→Suspended/Archived states.

## 14. API impact

Shared REST/GraphQL create, invite/self-register intake, duplicate-search, submit, review, approve/reject/revise, activate/suspend/archive and scoped read/export operations. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Vendor directory/profile/onboarding wizard, duplicate-review and approval timeline; internal procurement first, with a tenant-enabled scoped intake surface only when identity ownership is proven. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Scope vendor profile by tenant/company/branch and field policy; intake tokens expire and cannot read existing vendor data; legal/contact/document fields are minimized and protected. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor code/legal-name hash/status/category/service/coverage; use trigram duplicate candidates, cursor lists and asynchronous import/document validation. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record intake source, duplicate decision, legal/profile changes, lifecycle/approval, actor, config version, document links and downstream impact. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Adopt and extend existing Phase 2 vendor rows; map duplicates by evidence, never auto-merge legal entities, and preserve every old rate/source reference. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Prove canonical Phase 2 vendor/rate ownership and publish an ADR if ambiguous.
- Define vendor identity, duplicate review, lifecycle, source and no-reentry invariants.
- Implement schema/policies/services/APIs and accessible internal onboarding UX.
- Add tenant-configurable invitation/self-registration intake without authoritative access.
- Test migration, duplicates, lifecycle, isolation, import and downstream compatibility.

## 21. Main flow

Procurement creates or invites a vendor, validates duplicate/legal/service/coverage data, collects mandatory evidence, submits for governed review, and activates the same canonical vendor for downstream use.

## 22. Alternative flow

Bulk-import staged vendors, request revision, link an intake to an existing canonical vendor, or keep self-registration disabled per tenant.

## 23. Exception flow

Block duplicate ambiguity, invalid/foreign legal identity, missing required evidence, expired token, stale approval version, unauthorized scope or downstream conflict; preserve staged data and exact resume. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- One tenant-scoped canonical vendor identity is reused across costing, shipment, procurement and Finance.
- Self-registration is tenant-configurable and produces staged intake, not automatic approval or access.
- Legal-entity merge, suspension, blacklist, reactivation and archive require reason, evidence and governed downstream impact.
- Vendor resource references never duplicate Phase 5 fleet/driver/warehouse roots.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate tenant/company scope, legal/vendor-code uniqueness, service/coverage compatibility, required fields/documents, active configuration and lifecycle/version before mutation. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Procurement staff maintain drafts; designated reviewers approve; tenant admins configure intake; Finance/Operations read only permitted fields; vendor intake has no cross-record access. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

New/existing/duplicate vendors, multi-service/coverage, invited/self-registration disabled/enabled, missing docs, stale token, suspension/reactivation and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Vendor identity/duplicate/lifecycle/approval/idempotency database and service tests.
- RLS/RBAC/field policy, forged-token, cross-tenant and import isolation tests.
- Phase 2 rate, Operations assignment and Finance vendor-reference compatibility tests.
- PRC-VND-US-001 browser/accessibility E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Commercial cost lookup, shipment vendor references, actual cost, Finance vendor bill/AP and Platform master/search/import behavior. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Vendor identity/lifecycle/intake/duplicate/no-reentry contract and onboarding/revision/suspension/migration runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Disable new intake, preserve staged/approved identities and downstream references, revert compatible code/policies and reconcile duplicates before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Canonical vendor registration/onboarding works without re-entry.
- Mandatory evidence and approval gate activation.
- Self-registration remains scoped, optional and non-authoritative.
- Cross-tenant and downstream compatibility gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-252 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

