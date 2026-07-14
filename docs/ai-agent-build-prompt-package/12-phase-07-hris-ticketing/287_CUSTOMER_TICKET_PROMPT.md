# Prompt 287 — Customer-to-Tenant Ticket

**Prompt ID:** `CG-S12-HRT-015`  
**Package document:** `CG-AABPP-HRT-287`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-287.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-015` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Ticket Channels and Conversation; Epic: Canonical Multi-Channel Service Control; Capability: Customer-to-Tenant Service Ticket; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the customer-to-tenant ticket domain/API and a bounded verification surface using fixed Layer 4 customer scope without pulling full Customer Portal Step 13 forward.

## 5. Business value

Let customers raise traceable service issues while preventing cross-account, internal-note, linked-record and attachment leakage.

## 6. Source requirement

TKT-CUS-001..004 and Ticketing Customer-to-Tenant requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-286; verified customer account/site/user scope and canonical ticket model. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-288..297; Step 13 Customer Portal. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Extend canonical ticket/channel membership with customer account/company/site scope, customer requester/participants, customer-visible messages, tenant-internal notes and permitted linked-record references. Do not create a second portal ticket store.

## 14. API impact

Shared REST/GraphQL customer create/list/read/reply/attachment/close/reopen-as-configured endpoints and tenant service operations from the same ticket service; customer scope is derived from authenticated membership. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Minimal bounded customer ticket create/list/detail/thread surfaces sufficient for isolation and contract verification plus full internal service view; full portal shell/dashboard/account management remains Step 13. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Layer 4 customers see only assigned account/company/site tickets, customer-visible messages and authorized linked records/files; internal notes, other customers, tenant-only fields, support metadata and raw IDs remain hidden. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/channel/customer account/site/status/updated time; customer-scoped keyset queues, message pagination, safe search and policy-aware aggregate counts. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record customer membership/scope, creation/reply/file/link access, denied cross-account attempts, tenant internal actions, status/resolution and exports without leaking message content into generic logs. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Classify imported customer cases by verified account/site and message visibility; quarantine records with ambiguous requester/scope instead of broadening access. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define Layer 4 customer principal/scope and customer-visible ticket projection.
- Extend canonical schema/policies/service/API without a portal-specific ticket root.
- Implement bounded accessible customer contract surface and internal handling view.
- Enforce internal-note, linked-record, file, search/count and notification isolation.
- Test forged account/site/reference, revocation, thread ordering and Step 13 handoff.

## 21. Main flow

Authenticated customer user creates a ticket within an allowed account/site, tenant queue responds through customer-visible messages while using separate internal notes, and both sides follow governed status/resolution with scoped file/link access.

## 22. Alternative flow

Authorized user creates for another permitted site, adds permitted company participant, reopens within policy, or tenant converts an inbound case after verified customer mapping.

## 23. Exception flow

Deny forged account/site/customer/ticket/link IDs, internal-note access, unauthorized participant, revoked membership, unscanned file, stale thread/status or ambiguous imported scope; reveal no existence signal. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Customer tickets are canonical tickets with Layer 4 scope, not a separate portal datastore.
- Authenticated membership—not request payload—determines allowed customer account/company/site.
- Every message/file/link/count/search result has an explicit customer-safe projection; internal notes never cross it.
- A ticket link grants no customer access to the linked shipment/invoice/warehouse/vendor/user.
- Full Customer Portal UX, account management and loyalty remain Step 13.

## 25. Validation rules

Validate active customer membership, tenant/account/company/site, permitted category/channel, message visibility, attachment state, participant, linked-record authorization, lifecycle/version and idempotency.

## 26. Access rules

Customers access own permitted account/site tickets; tenant queue staff see scoped internal view; customer admins may see configured company scope; support access uses separate case-bound controls. Policies cover API, search, exports, cache and notifications. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Customer user/admin, multiple accounts/sites/tenants, internal/customer messages, participant changes, revoked membership, forged link/file IDs, stale version and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Customer channel/projection and membership-scope domain tests.
- Cross-account/site/tenant/internal-note/link/file/search/count negative tests.
- Message/status/idempotency/revocation/notification tests.
- REST/GraphQL customer/internal parity contract tests.
- Bounded customer and internal browser/accessibility/performance E2E.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Canonical internal ticket, customer membership/scope, shipment/invoice/warehouse customer projections, files/notifications and future Step 13 API contracts. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Customer ticket channel/API, Layer 4 scope, customer-safe projection, internal-note/file/link isolation and Step 13 handoff runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Disable new customer intake, keep existing customer-safe read where verified, revoke unsafe projections/cache, preserve threads, revert compatible code/policies and reconcile scope mapping. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Customer channel extends one canonical ticket model and fixed Layer 4 membership.
- Cross-account/site/internal-note/link/file/search inference tests pass.
- Bounded surface verifies the contract without implementing full Step 13 portal.
- Thread, idempotency, revocation, accessibility and performance gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-288 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

