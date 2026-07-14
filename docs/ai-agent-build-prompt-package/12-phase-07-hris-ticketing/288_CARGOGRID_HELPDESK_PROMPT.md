# Prompt 288 — Tenant-to-CargoGrid Helpdesk

**Prompt ID:** `CG-S12-HRT-016`  
**Package document:** `CG-AABPP-HRT-288`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-288.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-016` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Ticket Channels and Conversation; Epic: Canonical Multi-Channel Service Control; Capability: Tenant-to-CargoGrid Support Ticket; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the tenant-to-CargoGrid helpdesk channel with explicit tenant requester, Platform support queue and case-bound support access.

## 5. Business value

Give tenants a governed support path while separating platform support metadata and privileged sessions from tenant business data.

## 6. Source requirement

TKT-HLP-001..004 and Ticketing Tenant-to-CargoGrid Helpdesk requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-286..287; Platform Supreme/support access, impersonation and canonical ticket contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-289..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Extend canonical tickets with helpdesk channel, tenant requester/admin scope, Platform support queue/team, support severity/product area, environment/reference metadata, support-session grant references and tenant-visible versus Platform-internal messages.

## 14. API impact

Shared REST/GraphQL tenant create/list/read/reply/attachment and Platform support triage/assign/respond/resolve operations; support-access grant creation remains Platform authority and requires case/reference. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Tenant admin helpdesk create/list/detail and CargoGrid support queue/thread with explicit internal-note boundaries, support-session banner/link and redacted diagnostic attachment handling. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Tenant users see only their tenant helpdesk cases; CargoGrid support sees assigned case data and minimum diagnostics. Any business-data access or impersonation requires separate reasoned, time-bound, visibly bannered grant with MFA and audit. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index helpdesk tenant/severity/product/status/queue/assignee/updated time; keyset queues, thread pagination, async diagnostic processing and limited assignment notification realtime. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record tenant requester, severity/product, support assignment, message visibility, attachment/diagnostic access, support-grant request/use/expiry, impersonation correlation, status/resolution and denied access. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Import support cases with tenant identity and visibility classification; do not attach historical support sessions or broaden access when source evidence is missing. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define tenant versus Platform support principals and helpdesk message projections.
- Extend canonical ticket schema/policies/service/API and accessible dual-side UX.
- Bind support access/impersonation grants to case, reason, MFA, expiry and banner.
- Implement safe diagnostic attachments, notifications and audit correlation.
- Test cross-tenant/support-queue/internal-note/grant expiry and recovery.

## 21. Main flow

Authorized tenant admin/user opens a helpdesk case, CargoGrid support triages and communicates through tenant-visible messages, uses Platform-internal notes, and requests a separate case-bound privileged grant only if diagnostic access is necessary.

## 22. Alternative flow

API/email intake after verified tenant mapping, severity escalation, reassignment, tenant participant addition, diagnostic bundle, reopen or duplicate case link.

## 23. Exception flow

Deny cross-tenant case access, unsupported requester, internal-note leakage, unassigned support access, expired/replayed grant, missing MFA/reason, unscanned diagnostic or stale status; preserve case without granting business-data access. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Helpdesk is a canonical ticket channel; it does not make CargoGrid support a tenant user or create a fifth access layer.
- A support ticket alone grants no tenant data access; privileged access uses separate Platform support/impersonation controls.
- Support grants are case-, purpose- and time-bound, MFA-protected, visibly bannered and fully audited.
- Platform-internal notes and diagnostics remain hidden from tenant projections; tenant-visible replies are explicit.
- RPD-022 Supreme Admin absolute CRUD remains an accepted residual risk and must be disclosed.

## 25. Validation rules

Validate tenant requester/admin scope, Platform support queue/assignee, severity/product config, message projection, attachment scan, grant case/reason/MFA/expiry, lifecycle/version and idempotency.

## 26. Access rules

Tenant users see their permitted helpdesk cases; Platform support sees assigned/authorized cases; support managers see scoped queues; business data is inaccessible without a separate valid grant. APIs/search/export/realtime share policy. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Multiple tenants, tenant user/admin, support agent/manager, assigned/unassigned, internal/tenant messages, active/expired grant, MFA failure, diagnostic file and forged case/reference fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Helpdesk channel/principal/message-projection domain tests.
- Cross-tenant/unassigned/internal-note/support-grant/MFA/expiry negative tests.
- Support-session correlation/banner/audit and revoke tests.
- Thread/idempotency/file/notification/search/export tests.
- Tenant and support browser/accessibility/performance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Canonical ticket channels, Platform support/impersonation/MFA/audit, tenant membership, files/jobs/notifications and generic admin portals. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Helpdesk principal/channel, support queue, message visibility, privileged grant/impersonation, diagnostic privacy, escalation and incident/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Disable new helpdesk intake or privileged grants as needed, revoke active unsafe grants, preserve cases/threads/audit, revert compatible code/policy and reconcile assignments/notifications. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Helpdesk uses the canonical ticket model without changing fixed access layers.
- Ticket alone grants no business-data access; case-bound MFA/expiry/banner controls pass.
- Cross-tenant/internal-note/diagnostic/support-grant isolation passes.
- Dual-side UX, thread, audit, accessibility and performance gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-289 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

