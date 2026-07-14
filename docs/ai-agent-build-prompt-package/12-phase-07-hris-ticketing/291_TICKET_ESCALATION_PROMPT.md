# Prompt 291 — Ticket Escalation

**Prompt ID:** `CG-S12-HRT-019`  
**Package document:** `CG-AABPP-HRT-291`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-291.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-019` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: SLA, Assignment, Escalation and Knowledge; Epic: Deterministic Service Governance; Capability: Functional, Hierarchical and SLA Escalation; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned functional, hierarchical and SLA-driven escalation with idempotent actions, acknowledgement and recovery.

## 5. Business value

Surface stuck or high-risk cases to the correct authority before service commitments fail without causing notification storms.

## 6. Source requirement

TKT-SLA-001..004 and master Escalation capability. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-289..290; SLA clock, assignment, workflow and notification contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-292..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create escalation policy/version, trigger/condition, level/step, target queue/team/user/role, action, acknowledgement, suppression/cooldown, event, retry state and resolution linkage records.

## 14. API impact

Shared REST/GraphQL policy configure/preview/publish, manual escalate, acknowledge, suppress-by-authority, resolve/de-escalate and event/history operations; scheduled triggers use durable idempotent jobs. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Escalation policy/preview, ticket escalation timeline, breach/stuck queue, manual escalation/acknowledgement and failure/retry visibility with accessible complete states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Targets are channel/tenant/support scoped; escalation notifications use minimized fields and safe links; customer users see only configured service-status projection, never internal hierarchy, notes or recipients. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/channel/status/SLA due/escalation next-at/level/target; indexed due scans, chunked jobs, deduplicated notifications, cooldown and backpressure to prevent storms. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record policy/version/trigger inputs, selected target/action, acknowledgement, suppression/reason/expiry, retry/failure, notification result and final resolution. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map open escalations to explicit policy/event state and next action; avoid replaying old notifications or treating missing acknowledgement as success. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define escalation trigger, level, target, idempotency, cooldown and acknowledgement invariants.
- Implement policy/events/services/APIs, durable jobs and accessible control UX.
- Bind SLA breach, priority, inactivity, assignment failure and manual triggers.
- Implement safe notifications, retry/DLQ, suppression and reconciliation.
- Test storms, repeated triggers, target revocation, channel isolation and recovery.

## 21. Main flow

A published policy observes a deterministic trigger such as SLA threshold, priority or inactivity, creates one escalation event, targets the eligible authority, sends deduplicated notification/action, records acknowledgement and continues or resolves per policy.

## 22. Alternative flow

Authorized manual escalation, functional transfer, hierarchical step-up, customer communication, temporary suppression with expiry or de-escalation after resolution.

## 23. Exception flow

Keep ticket safe and retry/DLQ when target is unavailable, notification fails or policy is stale; block cross-tenant/support target, invalid suppression, duplicate event or unauthorized manual action. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- An escalation event is uniquely keyed by ticket, policy/version, trigger and level; retries never create duplicate actions.
- Escalation may notify, reassign or create approval/task only as explicitly configured and independently authorized.
- Suppression/cooldown requires authority, reason, expiry and never hides compliance reporting.
- Customer-visible status is separate from internal target, hierarchy, note and notification metadata.
- Autonomous AI severity/escalation remains Step 14.

## 25. Validation rules

Validate active ticket/SLA/assignment, trigger evidence, unique event key, policy/version, target eligibility/scope, action authorization, cooldown/suppression and acknowledgement before progression.

## 26. Access rules

Service managers configure; eligible agents/managers acknowledge or manually escalate; customers see safe status only; Platform support actions remain helpdesk/case scoped. Jobs and notifications enforce policy. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

SLA warning/breach, priority/inactivity/assignment failure, multi-level steps, repeated trigger/retry, missing/revoked target, suppression expiry, manual escalation and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Escalation policy/event/level/unique-key domain tests.
- Trigger/retry/DLQ/cooldown/suppression/acknowledgement tests.
- RLS/RBAC/cross-channel/target/customer-notification leakage negative tests.
- Notification storm/backpressure/reconciliation/load tests.
- Escalation timeline/queue browser/accessibility E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

SLA clocks, ticket lifecycle, assignment, Platform workflow/approval/jobs/notifications and channel message projections. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Escalation triggers/levels/targets, idempotency/cooldown/suppression, notification minimization, retry/DLQ/reconciliation and incident runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Pause faulty escalation job/policy, keep ticket/SLA state intact, restore prior published policy for new events, deduplicate/reconcile events and notifications before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Escalation triggers/actions are versioned, unique, idempotent and acknowledged.
- Retry/DLQ, suppression/cooldown and notification-storm controls pass.
- Channel/tenant/target/customer-projection isolation passes.
- Manual/revoked-target/recovery, accessibility and load gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-292 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

