# Prompt 301 — Customer Portal Dashboard

**Prompt ID:** `CG-S13-CPL-003`  
**Package document:** `CG-AABPP-CPL-301`  
**Version:** `0.14.0`  
**Runtime build log:** `docs/build-log/phase-08/CPL-301.md`

Do not begin until Prompt 299 marks this task `READY`, all variables are resolved, and `PHASE_7_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S13-CPL-003` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 8 — Customer Portal and Loyalty`; package `0.14.0`.

## 3. Workstream

Workstream: Portal Experience; Epic: Customer Self-Service Home; Capability: Customer Dashboard; Feature slice: Shipment, booking, invoice, ticket, loyalty and alert summary using safe pre-aggregated projections; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Build the mobile-friendly customer dashboard as a scoped projection surface over canonical Commercial, Operations, WMS, Finance, Ticketing and Loyalty services.

## 5. Business value

Give customers fast self-service visibility without exposing internal operational or financial data.

## 6. Source requirement

CPT-TRK-001..004, CPT-BIL-001..004, CPT-CX-001..004, LYL-ANL-001..004; Brief Customer Portal list; UX Customer Portal Dashboard; Delivery Phase 8.. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 7 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/customer/account/site/Finance/WMS/Operations/Ticketing/loyalty/data/phase-boundary conflict.

## 9. Upstream dependencies

CPL-300 and verified Phase 2–7 domain contracts.. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

CPL-302..323; dashboard cards deep-link into scoped flows only.. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Customer Portal, Tenant Internal, Commercial, Operations, WMS, Finance, Ticketing, Loyalty, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 8 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate customer/quote/shipment/warehouse/invoice/payment/ticket/loyalty roots, full Step 14–16 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Use pre-aggregated customer dashboard read models keyed by tenant, customer, account, site, source entity and config version; do not create duplicate source truth. Preserve canonical source-domain ownership and include tenant_id, customer_id/account_id/site_id where applicable, config/source versions, idempotency, audit and rollback-safe additive migrations.

## 14. API impact

Scoped dashboard summary APIs with cursor drilldowns, stale/degraded markers and identical REST/GraphQL field policies. REST and GraphQL must share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Responsive dashboard cards for bookings, shipments, warehouse orders, invoices, payments, tickets, loyalty balance/expiry and alerts with loading/empty/error/denied/stale states. Include keyboard/focus/labels, mobile-friendly responsive online-first behavior, loading/empty/error/denied/stale/conflict/degraded states, unsaved-change protection and no dead action.

## 16. Security impact

Enforce Layer 4 customer scope in database/service, not UI only; preserve tenant/customer/company/account/site/record/field/file policy, server-only secrets, private scanned files, scoped signed URLs, sensitive-access audit, MFA/current authorization for high-risk actions and RPD-022 residual-risk disclosure.

## 17. Performance impact

Use selective projections, server filter/sort/search, cursor pagination, pre-aggregated dashboard/read models where justified, async jobs for heavy work and measured evidence. No `SELECT *`, global realtime fanout, browser-loaded full dataset or unsafe cache shared across customers.

## 18. Audit impact

Record actor, customer scope, source/config versions, correlation/idempotency key, before/after or event chain, approval where applicable, file access, denial, outcome and privileged/support access evidence. Evidence must be source-linked and privacy-safe.

## 19. Data migration impact

Use additive or expand-and-contract migrations; never edit applied migrations. Adopt existing Platform, Commercial, Operations, WMS, Finance, Ticketing and Loyalty references through explicit mapping; rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Define safe dashboard read models and source freshness metadata.
- Implement summary APIs using only scoped projections and no internal-only fields.
- Build responsive dashboard cards and deep links with reauthorization.
- Add performance budgets, cache invalidation and stale/degraded UX.
- Test cross-customer counts, inference risks and source reconciliation.

## 21. Main flow

Customer opens the portal dashboard and sees only scoped summaries with safe drilldowns to booking, tracking, invoice, ticket and loyalty pages.

## 22. Alternative flow

If a source service is degraded, show the affected card as stale/degraded while preserving other cards and preventing unsafe fallback data.

## 23. Exception flow

Block forged customer scope, unauthorized field/file/source access, stale version, duplicate idempotency conflict, unscanned file, ledger imbalance, unresolved source mismatch or later-phase scope creep; preserve safe state and exact resume. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- Dashboard counts and snippets cannot reveal existence of out-of-scope records.
- Every deep link reauthorizes the target entity; dashboard visibility alone grants nothing.
- Pre-aggregation must carry source timestamp/config version and reconcile with source totals.
- No internal margin, vendor, payroll, support-only or hidden ticket note data appears.
- Mobile card layout must preserve the same policy as desktop.
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

- Customer Dashboard unit/service/database/API/contract tests.
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

Update Phase 8 build log, customer portal scope contract, source-domain ownership notes, API/schema/field policy, UX states, runbook, test evidence, traceability, dependency and rollback/handoff artifacts relevant to Customer Dashboard.

## 32. Rollback/recovery note

Disable affected portal/loyalty mutation path, keep source-domain truth intact, revert compatible code/policies and reconcile projections/ledgers/jobs/files before resume. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Customer Dashboard works with canonical source-domain ownership and no duplicate truth.
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

