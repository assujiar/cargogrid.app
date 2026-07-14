# Prompt 174 — Exception and Escalation

**Prompt ID:** `CG-S8-OPS-008`  
**Package document:** `CG-AABPP-OPS-174`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-174.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-008` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Control Tower; Epic: Operational Exception; Capability: Delay, hold, damage/loss/incident and SLA escalation; Feature slice: Detected exception→owner/SLA→notify/escalate→resolve/reopen; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement basic operational exception intake, ownership, SLA, escalation, notification and resolution linked to shipment/milestone evidence.

## 5. Business value

Ensure delays and incidents are visible, assigned and resolved instead of disappearing in chat.

## 6. Source requirement

OPS-TRK-001..004; OPS-DOC-001..004 basic Phase 3 slice; Brief exception/incident; Master Prompt Phase 3. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-173; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-175..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Control Tower schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend exception root/type/severity/status, shipment/milestone/document links, owner, SLA due, escalation level, resolution/reopen and basic damage/loss/incident intake fields.

## 14. API impact

Provide shared REST/GraphQL create/detect, assign, acknowledge, escalate, resolve, reopen and history operations; jobs enforce SLA reminders/escalation.

## 15. UI/UX impact

Build accessible exception queue/detail/timeline with severity, owner, SLA, evidence, resolution and complete states.

## 16. Security impact

Restrict customer/internal notes, damage/loss details, claim amount and attachments; escalation assignment follows hierarchy and record scope. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/status/severity/owner/due/shipment; paginate queues and make SLA jobs idempotent/bounded.

## 18. Audit impact

Record detection/source, severity/type, owner, SLA/escalation, notifications, evidence, resolution/reopen and protected access.

## 19. Data migration impact

Map legacy exceptions/incidents where shipment/type/status/time are known; full claim cases remain deferred/reconciled.

## 20. Detailed implementation tasks

1. Define basic exception/incident taxonomy, lifecycle, severity, SLA and escalation policy.
2. Implement manual/system event detection, assignment, resolve/reopen and idempotent SLA jobs.
3. Link milestones/documents and sanitized customer notification outcomes.
4. Build queue/detail/timeline UX and shared API contracts.
5. Verify escalation timing, access, concurrency, audit and advanced-claims boundary.

## 21. Main flow

Delay/incident creates one scoped exception, assigns an owner/SLA, escalates when due and resolves with evidence.

## 22. Alternative flow

Exception is downgraded/reassigned/reopened under configured authority while prior history remains.

## 23. Exception flow

Invalid source, duplicate detection, missing owner, notification failure, stale resolution or inaccessible evidence stays safely open/recoverable.

## 24. Business rules

- Full claims adjudication, insurance settlement and financial posting are not Phase 3.
- Severity/SLA/escalation rules are versioned and pinned at detection unless explicit reevaluation occurs.
- Resolution never deletes the underlying milestone/damage/loss evidence.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate type/severity, linked shipment/milestone, owner eligibility, SLA calendar and required evidence.
- Deduplicate system-detected events by source/correlation window.
- Customer notification uses sanitized policy and never exposes internal notes/cost.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Operations/control tower manages scoped exceptions; customers see only permitted status/message; claim/incident sensitive fields are restricted. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Delay/hold/damage/loss/incident, duplicate detection, SLA breach, reassignment, reopen, notification failure, restricted notes and two tenants. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Exception lifecycle/SLA/escalation/dedup/job/concurrency/database tests.
- RLS/RBAC/field/record/file/notification/API parity/audit tests.
- Queue/detail/timeline E2E, accessibility, SLA-job performance and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Milestones, shipment status, assignment, documents, tracking and future claims workflow. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-174.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Exceptions are owned, time-bound, escalated and resolved with evidence.
- Sensitive incident/claim data remains scoped.
- No full claims settlement or Finance scope is introduced.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-009` / `OPS-175` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

