# Prompt 145 — Contact and Activity Management

**Prompt ID:** `CG-S7-COM-004`  
**Package document:** `CG-AABPP-COM-145`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-145.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-004` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Customer Relationship; Epic: Relationship Workspace; Capability: Contact and activity management; Feature slice: Contact/site relationship plus call/email/meeting/visit/follow-up/task; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical contacts, addresses/sites and commercial activities reusable across lead, prospect, account, opportunity and quotation contexts.

## 5. Business value

Give sales one auditable relationship timeline and eliminate repeated PIC/address/activity entry.

## 6. Source requirement

COM-CRM-001..004; Brief §§6,7.1; UX commercial flow/data dictionary. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-143..144; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-146..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Customer Relationship schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend tenant-scoped contact, relationship role, address/site reference, communication preference, consent metadata and typed activity/task/reminder entities with polymorphic links constrained to permitted Commercial records.

## 14. API impact

Provide shared REST/GraphQL contact lookup/link/update and activity create/complete/reschedule operations; integrate notification/reminder jobs without provider-specific abstraction.

## 15. UI/UX impact

Build contact directory/detail and unified activity timeline with quick actions, due/overdue queues, permission-aware fields and complete responsive states.

## 16. Security impact

Protect PII, contact channels, notes and exports through field/record policy; activity participants and linked records must be accessible. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/account/contact/owner/type/due/status; paginate timelines and avoid per-row participant or linked-entity N+1 queries.

## 18. Audit impact

Record contact changes, relationship links, consent/preferences, activity actor/time/outcome, reassignment, reminder delivery and protected-field access.

## 19. Data migration impact

Normalize legacy contacts/addresses/activities by stable source IDs; do not collapse duplicates without reviewed reconciliation.

## 20. Detailed implementation tasks

1. Define canonical contact/address/site identity, relationship roles and activity taxonomy.
2. Implement scoped contact reuse/linking with duplicate candidates and preference/consent handling.
3. Implement activity/task/reminder lifecycle and notification hooks.
4. Build directory/detail/timeline/due-queue UI plus shared API contracts.
5. Prove no-reentry, PII access, recurrence/concurrency, audit and lineage.

## 21. Main flow

A seller reuses or creates one permitted contact, links it to the commercial entity and logs a completed or scheduled activity.

## 22. Alternative flow

A shared contact is linked to another permitted account/site role without copying the contact record.

## 23. Exception flow

Duplicate conflict, inaccessible account, invalid channel/preference, stale task or reminder failure is surfaced and recoverable.

## 24. Business rules

- One contact may have governed roles/relationships; access follows each relationship and tenant policy.
- Activities are append-oriented business history; corrections preserve before/after evidence.
- Addresses/sites are referenced canonically or snapshotted only for explicit transaction reasons.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Normalize email/phone/address identifiers and validate relationship cardinality.
- Activity type, start/due/completion, outcome and linked-record access are server-enforced.
- Notification preference and consent rules apply before external communication.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Sales sees permitted relationship records; private notes and PII/export fields require explicit permissions; support access remains time/purpose bound. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Shared and duplicate contacts, multiple addresses/sites/roles, calls/emails/meetings/visits/tasks, overdue/reminder failures and cross-scope cases. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Contact uniqueness/relationship/activity lifecycle/reminder database and job tests.
- PII field/record/RLS/RBAC/cross-tenant/API parity/audit tests.
- Directory/timeline/quick-action E2E, accessibility, pagination and no-reentry regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Lead/prospect/account links, notification engine, import/export, file attachments and existing contact/customer data. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-145.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Contacts and addresses are reused safely across Commercial records.
- Activity history and reminders are complete, accessible and auditable.
- No relationship or activity creates cross-tenant or unauthorized data exposure.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-005` / `COM-146` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

