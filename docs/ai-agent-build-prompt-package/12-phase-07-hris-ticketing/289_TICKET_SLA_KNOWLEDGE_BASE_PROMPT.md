# Prompt 289 — Ticket SLA and Knowledge Base

**Prompt ID:** `CG-S12-HRT-017`  
**Package document:** `CG-AABPP-HRT-289`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-289.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-017` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: SLA, Assignment, Escalation and Knowledge; Epic: Deterministic Service Governance; Capability: SLA Policy, Clock and Knowledge Article; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned deterministic ticket SLA clocks and audience-controlled knowledge articles across all three ticket channels.

## 5. Business value

Make response/resolution commitments measurable and reusable while keeping timers, pauses and guidance explainable.

## 6. Source requirement

TKT-SLA-001..004 and Ticketing SLA, Escalation & Knowledge Base requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-286..288; Platform configuration/calendar/jobs/notification and canonical ticket lifecycle. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-290..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create SLA policy/version, channel/category/priority/customer/service scope, business calendar/version, response/resolution target, clock instance, event/pause/resume/breach ledger and knowledge article/version/audience/review/publish/expiry/link records.

## 14. API impact

Shared REST/GraphQL SLA configure/validate/publish, clock read/recalculate-by-authorized-correction, article draft/review/publish/archive/search and ticket-article link operations; clock evaluation/reminders use durable idempotent jobs. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

SLA policy/calendar editor, ticket SLA indicators/timeline, breach queue and knowledge author/review/search/link surfaces with audience previews and accessible complete states. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

SLA policy is tenant/config scoped; customer users see only customer-safe target/status and published audience-permitted articles; internal/support articles and notes never leak through search, snippets, links or cache. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/policy/channel/category/priority/status/due time and article audience/status/tags; due-time queue scans by indexed windows, bounded article search and job backpressure/reconciliation. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record policy/calendar/article versions, publish/review, clock start/pause/resume/recalculate/breach, reminders, article view/link and audience/search denials. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Map existing targets/clocks to explicit policy/calendar versions and event ledgers; quarantine ambiguous pause/history instead of inventing SLA compliance. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define SLA selection, clock event, pause/calendar/version and compliance invariants.
- Implement policy/calendar/clock schema, APIs, durable jobs and ticket indicators.
- Implement knowledge article lifecycle, audience-safe search and ticket linking.
- Add reconciliation/replay, breach reminders and dashboard source contracts.
- Test timezones/calendars, retries, audience leakage, version changes and scale.

## 21. Main flow

A ticket selects one published SLA policy/version from channel/category/priority/scope, starts deterministic response/resolution clocks, processes allowed pause/resume events, emits idempotent reminders/breach events and offers only audience-permitted published knowledge.

## 22. Alternative flow

No matching policy fallback, customer-specific target, holiday/calendar change for future tickets, authorized clock correction with replay, article revision/expiry or manual link.

## 23. Exception flow

Block ambiguous/multiple policy match, missing calendar, invalid pause event, stale clock/article version, unauthorized correction/publication or audience leak; preserve prior clock and visible safe status. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Every ticket clock retains exact SLA and business-calendar versions selected at start; later config changes do not silently rewrite history.
- Response and resolution clocks, allowed pause reasons and terminal events are distinct and event-derived.
- Job retry/replay produces no duplicate reminder or breach; compliance is reproducible from the clock ledger.
- Knowledge articles require audience, reviewer, published version and expiry/review state; draft/internal content never appears to customers.
- AI article suggestion/summarization remains Step 14.

## 25. Validation rules

Validate unique policy precedence, channel/category/priority/scope, target duration/unit, calendar/timezone, event order, allowed pause/resume, article audience/reviewer/version and job idempotency.

## 26. Access rules

Service managers configure/publish; queue staff see permitted clocks/articles; customers see customer-safe clocks and published audience content; Platform support sees assigned helpdesk policy. Search/cache/export share audience policy. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Internal/customer/helpdesk policies, multiple priorities/calendars/timezones/holidays, pause/resume/reopen, retries/replay, breach, draft/internal/customer articles, expiry and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- SLA policy selection/calendar/clock-ledger/exact-due tests.
- Pause/resume/reopen/correction/version and job idempotency tests.
- RLS/RBAC/article audience/search/cache/link negative tests.
- Breach/reminder/reconciliation/dashboard-source tests.
- SLA indicator/knowledge browser/accessibility/load E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

All ticket channel lifecycle/messages, Platform config/calendar/jobs/notifications/search/cache and future Customer Portal article projection. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

SLA selection/precedence, calendar/clock events, pause/reopen/correction, job replay/reconciliation, knowledge lifecycle/audience and recovery runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Pause clock jobs/publication, preserve event ledgers and current published versions, restore prior safe policy for new tickets, replay idempotently and reconcile due/breach/article indexes. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- SLA due/compliance is deterministic from versioned policy, calendar and event ledger.
- Retry/replay cannot duplicate reminders or breaches.
- Knowledge draft/internal/customer audiences remain isolated across search/cache/link.
- Timezones, correction, accessibility, performance and Tenant A/B gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-290 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

