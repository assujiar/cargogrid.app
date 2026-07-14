# Prompt 326 — Customer Portal and Loyalty Documentation Handoff

**Prompt ID:** `CG-S13-CPL-028`  
**Package document:** `CG-AABPP-CPL-326`  
**Version:** `0.14.0`  
**Runtime build log:** `docs/build-log/phase-08/CPL-326.md`

Do not begin until all upstream tasks required by the execution index are `VERIFIED` and `PHASE_7_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S13-CPL-028` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 8 — Customer Portal and Loyalty`; package `0.14.0`.

## 3. Workstream

Workstream: Integrated Verification, Hardening, Documentation and Closure; Epic: Phase 8 Evidence Closure; Capability: Customer Portal and Loyalty Documentation Handoff; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Complete Phase 8 documentation, runbooks, traceability, handoff and exact Step 14 eligibility package after hardening.

## 5. Business value

Make Phase 8 reproducible, maintainable and handoff-ready without overstating runtime or GA status.

## 6. Source requirement

All `CPT-QBK`, `CPT-TRK`, `CPT-WHS`, `CPT-BIL`, `CPT-CX`, `LYL-PRG`, `LYL-PNT`, `LYL-RDM` and `LYL-ANL` requirements, Product Brief Customer Portal and Loyalty, UX Customer Portal/Loyalty, Technical Architecture/Security/Integration and Delivery Phase 8. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 7 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/customer/account/site/Finance/WMS/Operations/Ticketing/loyalty/data/phase-boundary conflict.

## 9. Upstream dependencies

CPL-325 VERIFIED. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

CPL-327 and Step 14 handoff only. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, Customer Portal, Tenant Internal, Commercial, Operations, WMS, Finance, Ticketing, Loyalty, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 8 documentation, runbook, evidence, handoff paths authorized by WBS. Resolve repository paths; preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New unplanned capability, duplicate roots, full Step 14–16 implementation, tenant forks, applied-migration edits, destructive cleanup, production mutation and hidden test/permission weakening.

## 13. Database impact

No planned feature schema except minimal registered defect repair. Inspect migrations, constraints, RLS, customer portal membership/scope, source-domain projections, document/file references, loyalty program/ledger/redemption/fraud/liability tables and source ownership.

## 14. API impact

Verify or document REST/GraphQL parity, authentication, authorization, field projection, idempotency, errors, cursor behavior, jobs/webhooks and domain handoffs across every Phase 8 service. Do not add unplanned endpoints. REST and GraphQL retain one service/auth/field policy/idempotency/audit/version contract.

## 15. UI/UX impact

Verify or document customer/admin journeys, all states, accessibility, browser/responsive online-first behavior, masked fields, signed file UX, loyalty wallet/reward/redemption states and no fake/dead action.

## 16. Security impact

Run or document cross-tenant/customer/company/account/site/record/field/file/link/cache/search/export/realtime abuse tests, MFA/high-risk controls, private scan/signed URL and RPD-022 residual-risk checks. Preserve RLS/RBAC, server-only secrets, private scanned files, field policy and evidence redaction.

## 17. Performance impact

Measure or document target-volume portal dashboard, tracking, documents, inventory/orders, invoices/payments, tickets, loyalty ledger/redemption/liability jobs and exports with declared environment/dataset/concurrency. Record no-regression threshold; no `SELECT *` or client-loaded full data.

## 18. Audit impact

Verify or document actor/source/config/customer-scope/correlation/idempotency/before-after/event-chain evidence, sensitive-access minimization, denial logging and reconciliation retrieval. Evidence must be useful, source-linked and privacy-safe.

## 19. Data migration impact

Verify or document clean install and Phase 7→8 upgrade, type generation, seed privacy, rollback/forward recovery, portal projection reconciliation, loyalty ledger/liability opening balance if any and no applied-history edits.

## 20. Detailed implementation tasks

- Update source-to-runtime traceability for all 24 capabilities and 36 anchors.
- Publish portal scope, source-domain ownership, API/schema, file, loyalty ledger, fraud/approval, liability and rollback runbooks.
- Update UX state coverage, accessibility evidence, performance profile and customer UAT scripts.
- Prepare Step 14 handoff boundaries for AI/predictive/reporting/automation/enterprise expansion.
- Reconcile persistent ledgers and exact resume/next prompt instructions.

## 21. Main flow

Documentation handoff reconciles runtime evidence, source mapping, operations runbooks and Step 14 boundaries at the current checkpoint.

## 22. Alternative flow

Parallelize truly non-overlapping test or documentation suites against the same build/schema/data profile, then reconcile to one final checkpoint before verdict.

## 23. Exception flow

On flaky, environment, source mismatch or pre-existing failure, prove classification with reruns and baseline evidence; never suppress. On privacy, scope, file, ledger, payment or liability leak, stop affected flow, preserve evidence and follow incident/rollback procedure. Record blocker, owner, exact reproduction and safe resume.

## 24. Business rules

- Evidence must come from one identified compatible checkpoint; mixed-commit results are invalid.
- All 24 capabilities and 36 anchors require code/contract/UI as applicable, tests, docs and owner or explicit blocker.
- Critical customer-scope, file, invoice/payment, ticket, loyalty-ledger, fraud, redemption or liability failure blocks closure.
- Package completion is not runtime implementation or evidence.
- No production, pilot, GA or market-ready claim.
- RPD-004 responsive online-first PWA; no native/offline-sync claim.
- Layer 4 Customer User scope is company/account/site/shipment/warehouse/invoice/document/ticket/loyalty only and must be database/service enforced.
- RPD-022 Supreme Admin absolute CRUD is accepted residual risk; never claim immutable-for-all or tamper-proof behavior.
- RPD-023 MFA/current authorization for privileged customer-admin, reward approval, export and support actions.
- RPD-025 retention: finance/tax 10 years, audit/security 7 years, operational contract+90, legal hold override.
- RPD-032 every upload is private and malware-scanned before release; signed URLs are short-lived and scope-bound.
- RPD-033 REST/GraphQL parity from one service/authorization/audit contract.
- RPD-040 active critical records retain applied configuration/source versions.
- Loyalty balances are derived from append-only ledger events for normal roles; direct balance mutation is forbidden outside explicit Supreme Admin residual-risk handling.

## 25. Validation rules

Validate checkpoint compatibility, requirement-to-evidence completeness, deterministic fixtures, expected versus actual, source/downstream totals, no orphan/cycle/collision and defect severity/ownership.

## 26. Access rules

Use least-privileged test roles for each fixed principal layer plus explicit denied roles; privileged/Supreme tests are isolated, reasoned and redacted. Evidence storage itself is access-controlled. Customer Portal evidence must prove company/account/site boundaries.

## 27. Test data requirement

Multi-tenant/customer/account/site portal fixtures covering quote, booking, shipment, ePOD, documents, warehouse inventory/order, invoice/payment, tickets, loyalty program/tier/points/benefits/rewards/redemption/expiry/fraud/liability, malicious files, retries/races and target volumes. Include source/config versions, allowed/denied roles and reproducible checkpoint/profile.

## 28. Tests to create/update

- 24-capability × 36-anchor traceability and critical-flow suite.
- Customer scope, field/file/source-link/cache/search/export/realtime negative matrix.
- Quote/booking/shipment/ePOD/document/inventory/invoice/payment/ticket source-domain reconciliation tests.
- Loyalty program/tier/point/cashback/reward/redemption/expiry/fraud/liability ledger exactness tests.
- REST/GraphQL parity, jobs/retry/DLQ, migration/recovery and observability tests.
- Responsive browser/WCAG and declared target-volume performance suite.

## 29. Regression tests

Run all critical Platform, Commercial, Operations, Advanced TMS/WMS, Finance, Procurement and HRIS/Ticketing tests touched by customer, shipment, invoice, warehouse, ticket, user, file, job, payment or loyalty contracts.

## 30. Commands to run

Run repository lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security/build gates plus relevant migration, job, replay/load, failure/recovery and reconciliation commands. Never disable or suppress a gate.

## 31. Documentation to update

Integrated evidence index, traceability matrix, critical-flow results, customer scope matrix, loyalty ledger/liability reconciliation, file/access/security report, performance profile, migration/recovery report, defect register and CPL-326 build log. Update persistent ledgers/traceability and exact resume instructions.

## 32. Rollback/recovery note

If work mutates test state, reset only through supported fixtures/transactions; for defects restore last trusted checkpoint, preserve evidence and give exact bounded resume. State the last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every Phase 8 capability and 36 anchor has current source-to-runtime evidence or explicit blocker.
- Customer Portal flows prove account/site isolation and source-domain ownership.
- Loyalty flows prove ledger exactness, fraud/approval, expiry, redemption and liability reconciliation.
- Tenant/field/file/API/job/migration/performance gates execute without suppression.
- No unresolved critical/high blocker may advance; findings are ranked and owned.

## 34. Definition of Done

All scoped evidence/repairs/docs, contracts, migrations if any, RLS/RBAC/field policy, APIs, UX, jobs, tests, audit, performance and rollback are complete; no critical tenant/customer/source-domain/file/payment/ticket/loyalty blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; changed files/migrations/contracts; commands/results; capability/anchor or finding matrix; tenant/customer/account/site/access/file/source-domain/loyalty/idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release CPL-327 after this task is `VERIFIED`. Do not set the final Phase 8 closure flag; only Prompt 327 may do so.

