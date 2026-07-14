# Prompt 267 — Optional Vendor Portal

**Prompt ID:** `CG-S11-PRC-018`  
**Package document:** `CG-AABPP-PRC-267`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-267.md`

Do not begin until Prompt 250 marks this task `READY`, all variables are resolved, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-018` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Vendor Experience; Epic: Tenant-Enabled External Collaboration; Capability: Scoped Vendor Self-Service Portal; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement an optional tenant-enabled vendor collaboration surface for onboarding evidence, RFQ responses, capacity, PO acknowledgement, disputes and allowed score/status without creating a fifth access layer.

## 5. Business value

Reduce manual vendor communication while maintaining strict external-party isolation and internal decision authority.

## 6. Source requirement

Master Prompt optional vendor portal, BP-A08, PRC-VND/RTE/SRC/POI-001..004 and RPD-004/005/019/033. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant handoff/build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, run feasible baselines, state plan/files, and stop on tenant/vendor/security/financial/data/phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..266; explicit Platform identity/membership ADR and all internal source contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-268..271. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Procurement/Vendor schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate vendor/rate/Operations/Finance roots, full Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Add only vendor-account memberships/grants/invitations/sessions/preferences and permitted portal action/read projections tied to canonical vendor records; do not duplicate vendor, RFQ, capacity, PO, match or document truth.

## 14. API impact

Shared REST/GraphQL vendor-scoped onboarding/document, RFQ response, capacity, PO acknowledgement, dispute/evidence and permitted status/score operations through existing domain services. REST and GraphQL share one domain service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Controlled white-label responsive online-first portal with invitation/recovery, dashboard/tasks, onboarding/docs, RFQ, capacity, PO, disputes and allowed score/status; no internal menu or customer portal data. Include loading, empty, error, success, permission-denied, stale/conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Resolve external vendor identity within approved four-layer Platform model/ADR; deny by default; vendor-account/tenant/record/action/field/file scope, MFA configuration, rate limits, anti-enumeration, revocation and support audit. Preserve tenant/company/branch/vendor/record/field scope, RLS, RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/vendor account/membership/status/action/date; task-centric cursor queries, bounded uploads/exports, limited realtime and RPD-014 budgets. Use selective columns, server filter/sort/search, cursor pagination, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record invitation/accept/revoke, membership/grant, login/recovery, every portal read/write/download, domain source/version, denial and support impersonation/session evidence. Include correlation/idempotency key, actor/context, source/config versions, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

No vendor portal membership is inferred from contact email; invite and verify identities explicitly, map only evidenced existing accounts and default ambiguous links denied. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Resolve four-layer external vendor identity/membership ownership; block if ambiguous.
- Define tenant enablement, entitlements, vendor grants, fields/actions and revocation.
- Implement portal shell and shared domain-service operations without duplicate truth.
- Apply white-label/custom domain, accessibility, files, session and support controls.
- Test cross-vendor/customer/tenant isolation, token recovery, load and all portal workflows.

## 21. Main flow

Tenant enables the portal, authorized staff invite a verified vendor contact, membership is bound to one vendor scope, and the user performs only granted tasks against canonical internal records.

## 22. Alternative flow

Keep portal disabled and use scoped one-time action links; support multiple vendor contacts/roles, revoke access, or delegate a bounded action.

## 23. Exception flow

Deny unenabled tenant, unverified/expired invitation, ambiguous vendor link, foreign customer/vendor record, forbidden field/action, revoked user, unsafe file, rate-limit or stale task. Record blocker/error/issue and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Optional means tenant-configurable, not incomplete: when enabled, every exposed workflow must meet full security/UX/test gates.
- Do not create a fifth access layer or clone the Customer Portal; use an approved Platform external-party membership model/ADR.
- Portal is a projection/action surface over canonical domains, never a parallel vendor/RFQ/PO/match store.
- External vendors cannot approve themselves, select competitors, see internal cost/margin/budget, post Finance or mutate Operations execution.
- Extend canonical Phase 2–5 records and source/version lineage; no duplicate truth or silent re-entry.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous commitment, offline sync or partial-GA claim.

## 25. Validation rules

Validate tenant entitlement/enablement, identity/invitation/membership/vendor grant, requested action/field/record/file scope, current domain state/version and rate limits. Reject tenant/company/branch/vendor/source/config/version mismatch and stale concurrent mutation. Every state, assignment, sensitive change or handoff is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Vendor admins/users get tenant-configured own-vendor roles; Procurement governs memberships/actions; Platform support is time/purpose-bound; customer and internal scopes remain separate. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same field and record policy.

## 27. Test data requirement

Portal disabled/enabled, one vendor multiple contacts/roles, one contact forbidden cross-vendor, expired/revoked invite, customer-user collision, restricted fields, unsafe file and Tenant A/B. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Identity/invitation/membership/grant/revocation/recovery tests.
- Cross-tenant/vendor/customer/record/field/file/action isolation and enumeration tests.
- Shared REST/GraphQL parity, session/rate-limit/custom-domain/white-label tests.
- Onboarding→RFQ→capacity→PO acknowledgement→dispute portal accessibility/load E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Platform identity/custom domain/branding/support, customer portal isolation, all Procurement domain services, files/notifications and audit. Re-run tenant/vendor isolation, financial/Operations compatibility, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add relevant database migration/type generation, security/dependency, job/integration, import/load and browser E2E commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Vendor portal enablement/identity/grant/action/field/revocation/shared-service contract and invite/recovery/leakage/support runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts and user/admin/API/support docs.

## 32. Rollback/recovery note

Disable tenant portal or affected action, revoke sessions/tokens, preserve canonical domain records/audit and verify internal workflows continue before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Portal can be disabled or securely enabled per tenant.
- Vendor identity fits the approved four-layer model without customer/data collision.
- All actions reuse canonical services and deny cross-scope access.
- Responsive/accessibility/API/file/session/load gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/vendor/financial/Operations blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/vendor/access/financial/Operations evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-268 or another dependency-clean atomic task after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

