# Prompt 286 — Internal and Interdepartmental Ticket

**Prompt ID:** `CG-S12-HRT-014`  
**Package document:** `CG-AABPP-HRT-286`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-286.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-014` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Ticket Channels and Conversation; Epic: Canonical Multi-Channel Service Control; Capability: Internal and Interdepartmental Ticket; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the internal ticket channel on one canonical ticket/conversation model with requester, department queue, private notes and lifecycle control.

## 5. Business value

Replace chat/email handoffs with accountable service requests, visible ownership, searchable evidence and measurable resolution.

## 6. Source requirement

TKT-INT-001..004 and Ticketing Internal/Interdepartmental requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-273; Platform user/org/workflow/file/notification/job foundations and verified canonical linked records. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-287..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create or extend canonical ticket, channel, requester, category/priority, queue, status/history, conversation message, visibility, watcher, attachment and resolution records. Internal channel principals are Layer 3 tenant users and department scope is explicit.

## 14. API impact

Shared REST/GraphQL create, read, list/search, reply, internal-note, watch, change status/category/priority, resolve/reopen and export operations using one ticket service and idempotent message mutation. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Internal ticket list/queue and detail thread with requester/assignee/status/SLA/link metadata, reply versus internal note distinction, attachments and complete responsive accessible states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Tenant/internal ticket scope follows requester, queue, department, participant, explicit watcher and permission rules; internal notes never leak to customer channel projections; attachments are private/scanned. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/channel/status/priority/queue/requester/assignee/updated time; keyset ticket queues, message pagination, bounded search and limited assignment/message notification realtime. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record ticket creation/source, channel/category/priority/status, participant/visibility, message/edit/redaction, attachment access, assignment/escalation/resolution and exports. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Import legacy internal tickets/messages with channel and visibility classification; preserve source order/time and quarantine ambiguous private/public notes. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define canonical ticket, internal channel principal and message visibility invariants.
- Implement schema/policies/shared APIs and accessible internal queue/thread UX.
- Bind category/status/workflow, files, notification and audit primitives.
- Prepare SLA/assignment/escalation/link extension points without duplicate models.
- Test thread ordering, visibility, isolation, concurrency, search and lifecycle.

## 21. Main flow

An authorized internal user creates a categorized ticket, the target department queue receives it, participants converse with explicit public-to-requester versus internal-note visibility, ownership/status progresses and resolution is acknowledged/closed.

## 22. Alternative flow

Email/API import, on-behalf request by authorized service desk, watcher addition, department transfer, duplicate merge/link, reopen or cancellation.

## 23. Exception flow

Block cross-tenant/department access, invalid queue/category/status transition, leaked internal note, replayed message, unscanned attachment or stale thread/status version; preserve the ticket and safe resume. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- All ticket channels reuse one canonical ticket/message model with explicit channel and visibility; channel does not imply universal access.
- Internal note and requester-visible reply are distinct server-enforced message types.
- Requester, participant, watcher and queue access are explicit and revocable; department membership alone may be insufficient.
- Ticket creation, reply and status mutation are idempotent and ordered; silent message overwrite is prohibited.
- AI classification/summarization stays Step 14.

## 25. Validation rules

Validate tenant/principal, channel/category/queue, requester authority, message visibility, attachment scan, status transition, participant/watch policy, idempotency and optimistic version.

## 26. Access rules

Layer 3 requester sees own/participating tickets; queue staff see eligible queues; managers see scoped reports; service admins configure within tenant. Database/service policy governs thread/search/export/realtime. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Requester/queue staff/manager, multiple departments, internal/public notes, watchers, transfers, duplicate message/retry, malicious attachment, stale status and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Canonical ticket/channel/message/status domain tests.
- RLS/RBAC/requester/queue/watcher/internal-note/cross-tenant negative tests.
- Message order/idempotency/concurrency/file/notification tests.
- Search/export/realtime policy and lifecycle tests.
- TKT-LST/DET internal browser/accessibility/performance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Platform workflow/status/files/notifications/jobs/audit, user/department revocation and generic search/export contracts. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Canonical ticket/internal channel, queue/participant/visibility, conversation/file, lifecycle/reopen and import/recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Disable new internal intake if unsafe, preserve tickets/thread order, quarantine ambiguous messages/files, revert compatible code/policies and reconcile notifications/indexes. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Internal/interdepartmental tickets use the canonical model and ordered auditable thread.
- Requester/queue/watcher/internal-note isolation and revocation pass.
- Lifecycle, files, idempotency, search and notifications pass.
- Tenant A/B, accessibility and performance gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-287 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

