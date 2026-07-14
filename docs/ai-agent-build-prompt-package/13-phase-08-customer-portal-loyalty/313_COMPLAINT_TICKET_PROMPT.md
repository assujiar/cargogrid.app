# Prompt 313 — Complaint and Ticket

**Prompt ID:** `CG-S13-CPL-015`  
**Package document:** `CG-AABPP-CPL-313`  
**Version:** `0.14.0`  
**Runtime build log:** `docs/build-log/phase-08/CPL-313.md`

Do not begin until Prompt 299 marks this task `READY`, all variables are resolved, and `PHASE_7_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S13-CPL-015` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 8 — Customer Portal and Loyalty`; package `0.14.0`.

## 3. Workstream

Workstream: Portal Customer Service; Epic: Customer Service Requests; Capability: Complaint and Ticket; Feature slice: Customer complaint, claim, service request, feedback and linked portal record tickets; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement customer portal ticket entry and visibility as a safe projection/action surface over the canonical Ticketing model from Phase 7.

## 5. Business value

Give customers a structured service channel while preserving internal/customer note boundaries and SLA integrity.

## 6. Source requirement

CPT-CX-001..004, TKT-CUS-001..004, TKT-SLA-001..004; Brief Complaint/Ticketing; UX Ticket.. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 7 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/customer/account/site/Finance/WMS/Operations/Ticketing/loyalty/data/phase-boundary conflict.

## 9. Upstream dependencies

CPL-300 and Step 12 customer ticket/SLA/assignment/link/file contracts.. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

CPL-306, CPL-308, CPL-311 and dashboard alert/status flows.. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Customer Portal, Tenant Internal, Commercial, Operations, WMS, Finance, Ticketing, Loyalty, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 8 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate customer/quote/shipment/warehouse/invoice/payment/ticket/loyalty roots, full Step 14–16 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Use canonical ticket/channel/message/link tables; add portal defaults only if needed, never duplicate ticket roots. Preserve canonical source-domain ownership and include tenant_id, customer_id/account_id/site_id where applicable, config/source versions, idempotency, audit and rollback-safe additive migrations.

## 14. API impact

Ticket create/list/detail/reply/close/reopen/link/file APIs with customer-visible reply policy, SLA status and linked-record reauthorization. REST and GraphQL must share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Ticket center with complaint/claim/service/feedback categories, linked shipment/invoice/warehouse/document, thread, SLA status and safe internal-note separation. Include keyboard/focus/labels, mobile-friendly responsive online-first behavior, loading/empty/error/denied/stale/conflict/degraded states, unsaved-change protection and no dead action.

## 16. Security impact

Enforce Layer 4 customer scope in database/service, not UI only; preserve tenant/customer/company/account/site/record/field/file policy, server-only secrets, private scanned files, scoped signed URLs, sensitive-access audit, MFA/current authorization for high-risk actions and RPD-022 residual-risk disclosure.

## 17. Performance impact

Use selective projections, server filter/sort/search, cursor pagination, pre-aggregated dashboard/read models where justified, async jobs for heavy work and measured evidence. No `SELECT *`, global realtime fanout, browser-loaded full dataset or unsafe cache shared across customers.

## 18. Audit impact

Record actor, customer scope, source/config versions, correlation/idempotency key, before/after or event chain, approval where applicable, file access, denial, outcome and privileged/support access evidence. Evidence must be source-linked and privacy-safe.

## 19. Data migration impact

Use additive or expand-and-contract migrations; never edit applied migrations. Adopt existing Platform, Commercial, Operations, WMS, Finance, Ticketing and Loyalty references through explicit mapping; rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Bind portal complaint categories to canonical Ticketing types and SLA policies.
- Implement scoped ticket create/thread/file/link APIs with customer-visible message rules.
- Build responsive ticket center and linked-record picker with reauthorization.
- Add SLA/status notifications and closure confirmation.
- Test internal note leakage, linked-record access, attachment scan, reopen and cross-customer search/counts.

## 21. Main flow

Customer opens a complaint linked to a shipment/invoice, exchanges customer-visible replies and tracks SLA/status until closure.

## 22. Alternative flow

A customer can create feedback or service request without a linked record; internal assignment/routing still follows Step 12 rules.

## 23. Exception flow

Block forged customer scope, unauthorized field/file/source access, stale version, duplicate idempotency conflict, unscanned file, ledger imbalance, unresolved source mismatch or later-phase scope creep; preserve safe state and exact resume. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Ticketing remains canonical; Customer Portal is not a duplicate helpdesk datastore.
- Internal notes, support-only fields, assignment workload and hidden links never leak to customers.
- A linked record grants no ticket access and a ticket grants no source-record access; both are reauthorized.
- SLA clocks/status shown to customers must derive from canonical SLA ledger/policy version.
- Attachments are private, scanned and audience-scoped.
- RPD-004 responsive online-first PWA; no native/offline-sync claim.
- Layer 4 Customer User scope is company/account/site/shipment/warehouse/invoice/document/ticket/loyalty only and must be database/service enforced.
- RPD-022 Supreme Admin absolute CRUD is accepted residual risk; never claim immutable-for-all or tamper-proof behavior.
- RPD-023 MFA/current authorization for privileged customer-admin, reward approval, export and support actions.

## 25. Validation rules

Validate tenant/customer/company/account/site/user/source-record scope, required fields, lifecycle, source/config version, idempotency, concurrency, file scan status, approval state where applicable and downstream reconciliation before mutation. Reject cross-tenant references, stale updates and unsafe inferred access.

## 26. Access rules

Customer users see and act only inside effective Layer 4 membership. Customer admins manage only delegated users/profile/scope inside their customer scope. Tenant internal roles use internal authorization and must not leak internal-only fields to portal surfaces. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Tenant A/B, multiple customers, accounts, sites, portal admins, portal ops, portal finance, revoked users, forged IDs, shipments, warehouse orders/inventory, invoices/payments, tickets, loyalty accounts/programs/ledgers/rewards/files, duplicate retries, stale versions and target-volume fixtures. Include deterministic IDs, allowed/denied roles and source/config versions.

## 28. Tests to create/update

- Complaint and Ticket unit/service/database/API/contract tests.
- Layer 4 tenant/customer/account/site/record/field/file isolation and negative tests.
- REST/GraphQL parity, idempotency, concurrency, source-version and audit tests.
- Responsive browser/accessibility tests for desktop/mobile customer portal states.
- Integration tests against Commercial, Operations, WMS, Finance, Ticketing, Platform files/jobs and Loyalty contracts as applicable.
- Migration/rollback/performance/security smoke coverage proportional to risk.

## 29. Regression tests

Re-run critical Platform identity/access/files/jobs, Commercial quote/customer, Operations shipment/ePOD, WMS inventory/order, Finance invoice/payment, Ticketing customer/SLA/link and previous portal/basic tracking suites touched by this task. Compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/replay/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Update Phase 8 build log, customer portal scope contract, source-domain ownership notes, API/schema/field policy, UX states, runbook, test evidence, traceability, dependency and rollback/handoff artifacts relevant to Complaint and Ticket.

## 32. Rollback/recovery note

Disable affected portal/loyalty mutation path, keep source-domain truth intact, revert compatible code/policies and reconcile projections/ledgers/jobs/files before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Complaint and Ticket works with canonical source-domain ownership and no duplicate truth.
- Layer 4 customer scope and field/file policy are enforced across database/service/API/UI/jobs/exports.
- REST/GraphQL, idempotency, audit, performance, migration, rollback and responsive UX gates pass.
- Source/config versions and downstream reconciliation evidence are recorded.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/customer/Finance/WMS/Operations/Ticketing/loyalty/file blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/customer/account/site/access/privacy/file/source-domain/loyalty evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release the next dependency-clean CPL prompt after this task is `VERIFIED`. Do not set the final Phase 8 closure flag; only Prompt 327 may do so.

