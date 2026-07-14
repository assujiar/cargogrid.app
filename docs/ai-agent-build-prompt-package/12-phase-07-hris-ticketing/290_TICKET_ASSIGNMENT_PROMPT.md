# Prompt 290 — Ticket Assignment

**Prompt ID:** `CG-S12-HRT-018`  
**Package document:** `CG-AABPP-HRT-290`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-290.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-018` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: SLA, Assignment, Escalation and Knowledge; Epic: Deterministic Service Governance; Capability: Queue, Team and User Assignment; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement explainable rule-based ticket routing and governed queue/team/user assignment across internal, customer and helpdesk channels.

## 5. Business value

Put each case with an eligible owner quickly while preserving workload visibility, revocation and channel isolation.

## 6. Source requirement

All TKT families and master Assignment capability. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-286..289; effective user/employee/team/queue and SLA contracts. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-291..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create assignment rule/version, eligible queue/team/user criteria, assignment event, claim/accept/decline/reassign, workload snapshot/reference, delegation/availability reference and assignment reason/source records. Reuse canonical user/employee/team identities.

## 14. API impact

Shared REST/GraphQL routing preview, auto-route, manual assign, claim/unclaim, accept/decline, reassign/transfer and assignment history operations with concurrency, idempotency and current eligibility checks. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Queue backlog, assignment drawer with explainable eligibility, my/team work, claim/reassign/transfer actions and workload indicators; accessible table/list alternatives and complete realtime/degraded states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Assignee candidates and workload are channel/tenant/queue scoped; customer requesters cannot select or enumerate internal/support users; helpdesk support queues remain Platform-side; assignment never broadens linked-record access. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/channel/queue/assignee/status/priority/SLA due/updated time; keyset queues, bounded candidate queries, optimistic claim locks and limited assignment realtime with fallback polling. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record routing rule/version/input/result/exclusions, manual override/reason, claim/accept/decline/reassign, eligibility/workload snapshot and notification outcome. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map legacy owner/queue values to canonical identities with unresolved quarantine; do not assign inactive or unverified users merely to satisfy migration totals. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define channel queue, eligibility, routing precedence and assignment concurrency invariants.
- Implement rules/events/services/APIs and accessible queue/assignment UX.
- Bind effective employee/user/team status, availability/delegation and SLA priority.
- Implement idempotent notifications, realtime fallback and workload reconciliation.
- Test races, revocation, cross-channel/tenant isolation, scale and no-AI boundary.

## 21. Main flow

Ticket creation or transfer selects an eligible queue from the published rule version; an authorized agent claims/accepts or manager assigns an eligible user with atomic concurrency, reason/source and SLA-aware notification.

## 22. Alternative flow

Manual queue assignment, round-robin/configured deterministic routing, agent decline, delegation, temporary unavailability, bulk reassignment after revocation or cross-department transfer.

## 23. Exception flow

Block no eligible queue/user, inactive/revoked assignee, cross-tenant/channel candidate, stale claim race, overload threshold or notification failure; keep ticket safely queued and surface exact remediation. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Assignment references canonical Platform user/HR employee/team identities and never copies an assignee master.
- Eligibility is evaluated server-side from channel, queue, permission, effective employment/membership, availability and configured skill/category.
- Assignment changes do not grant access to linked shipment/invoice/warehouse/vendor/customer records beyond independent policy.
- Claim/assign/reassign is atomic and idempotent; one current owner state has a complete event history.
- Routing is explainable rule-based control; AI triage/recommendation remains Step 14.

## 25. Validation rules

Validate ticket/channel/status, queue/rule version, candidate tenant/team/employment/access/availability, workload limit, delegation, current assignment version and idempotency before mutation.

## 26. Access rules

Queue agents see/claim eligible tickets; managers assign within governed scope; requesters/customers see only safe owner/team labels if configured; Platform support assignment remains helpdesk-scoped. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Internal/customer/helpdesk queues, active/inactive/revoked agents, multiple teams, delegation/unavailability, claim race, overload/no candidate, transfer/retry and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Assignment rule/eligibility/event/current-owner domain tests.
- Atomic claim/race/idempotency/reassign/revocation tests.
- RLS/RBAC/candidate enumeration/cross-channel/link-access negative tests.
- Notification/realtime fallback/workload reconciliation/load tests.
- Queue/assignment browser/accessibility/performance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Ticket channels/thread/status/SLA, Platform users/teams/notifications/realtime and HR effective employment/manager scope. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Queue/routing precedence, eligibility, claim/reassign, availability/delegation, notification/realtime fallback and bulk-revocation recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Disable faulty routing version, leave tickets in safe queue, restore prior published rule for new routing, atomically reconcile current/event assignments and notifications. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Routing and assignment are versioned, explainable and use canonical identities.
- Atomic claim/race, revocation, no-candidate and workload behavior pass.
- Channel/tenant/candidate/link isolation and notification/realtime fallback pass.
- Accessibility, load and reconciliation gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-291 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

