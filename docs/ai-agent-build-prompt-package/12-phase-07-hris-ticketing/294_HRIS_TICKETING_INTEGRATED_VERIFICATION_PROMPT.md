# Prompt 294 — HRIS and Ticketing Integrated Verification

**Prompt ID:** `CG-S12-HRT-022`  
**Package document:** `CG-AABPP-HRT-294`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-294.md`

Do not begin until all upstream tasks are `VERIFIED` and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-022` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Integrated Verification, Hardening, Documentation and Closure; Epic: Phase 7 Evidence Closure; Capability: Cross-Capability Verification; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Independently verify the 20 Phase 7 capabilities and cross-domain critical flows at one repository/schema/environment checkpoint before hardening.

## 5. Business value

Detect identity, time, payroll, privacy, channel, SLA and linked-record failures that isolated capability tests cannot prove.

## 6. Source requirement

All HRS-EMP/REC/ATT/PAY/KPI/ESS and TKT-INT/CUS/HLP/SLA requirements, HRS-ATT-US-001, Product Brief, UX, Technical Architecture and Delivery Phase 7. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..293 all VERIFIED. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-295..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 verification, repair, test, evidence and documentation paths authorized by WBS. Resolve repository paths; preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New unplanned capability, duplicate roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, production mutation and hidden test/permission weakening.

## 13. Database impact

No planned feature schema. Inspect migrations, constraints, RLS, effective versions, employee/time/payroll ledgers/snapshots, canonical ticket/channel/message/SLA/link tables and source ownership; allow only minimal registered verification-defect repair.

## 14. API impact

Verify REST/GraphQL parity, authentication, field projection, idempotency, errors, cursor behavior, jobs/webhooks and domain handoffs across every Phase 7 service. Do not add unplanned endpoints. REST and GraphQL retain one service/auth/field policy/idempotency/audit/version contract.

## 15. UI/UX impact

Verify employee/manager/HR/payroll/customer/support journeys, all states, accessibility, browser/responsive online-first behavior, masked fields, thread visibility and no fake/dead action. Preserve responsive/accessibility evidence, complete states and no fake success/dead action.

## 16. Security impact

Run cross-tenant/company/branch/department/employee/customer/site/channel/support/field/file/link abuse tests, MFA/high-risk controls, private scan/signed URL and RPD-022 residual-risk checks. Preserve RLS/RBAC, server-only secrets, private scanned files, field policy, RPD-022 disclosure and evidence redaction.

## 17. Performance impact

Measure target-volume employee directory, attendance capture/calendar, roster/leave queues, payroll batch/recovery, ESS/MSS, ticket queues/threads/search/SLA jobs/dashboard/export with declared environment/dataset/concurrency. Record before/after or verification profile and no-regression threshold; no `SELECT *` or client-loaded full data.

## 18. Audit impact

Verify end-to-end actor/source/config/correlation/idempotency/before-after/event-chain evidence, sensitive-access minimization, denial logging and reconciliation retrieval. Evidence must be useful, source-linked and privacy-safe.

## 19. Data migration impact

Verify clean install and Phase 6→7 upgrade, type generation, seed privacy, rollback/forward recovery, imported employee/time/ticket reconciliation and no applied-history edits. Never edit applied migrations or fabricate history; record backup, rollback and reconciliation.

## 20. Detailed implementation tasks

- Freeze one checkpoint and reconcile every task, anchor, file, migration, contract, test and evidence link.
- Execute employee→time→payroll→Finance and recruitment→onboarding critical flows.
- Execute all three ticket channels through assignment, SLA, escalation, typed links, files and closure.
- Run privacy/tenant/customer/support/API/job/performance/migration/recovery matrices.
- Rank every finding; repair only bounded authorized defects or block hardening with exact owner/resume.

## 21. Main flow

Verification freezes the checkpoint, runs source-to-runtime traceability and critical flows, reconciles outputs/side effects and produces a signed evidence matrix with pass/fail and reproducible defects.

## 22. Alternative flow

Parallelize truly non-overlapping test suites against the same build/schema/data profile, then reconcile to one final checkpoint before verdict.

## 23. Exception flow

On flaky, environment or pre-existing failure, prove classification with reruns and baseline evidence; never suppress. On integrity/privacy leak, stop affected flow, preserve evidence and follow incident/rollback procedure. Record blocker, owner, exact reproduction and safe resume.

## 24. Business rules

- Verification evidence must come from one identified compatible checkpoint; mixed-commit results are invalid.
- All 20 capabilities and 40 anchors require code/contract/UI as applicable, automated/manual tests, docs and owner.
- Critical identity/payroll/privacy/customer/support/link failure blocks the phase regardless of average pass rate.
- Package completion is not runtime implementation or evidence.
- No production, pilot, GA or market-ready claim.

## 25. Validation rules

Validate checkpoint compatibility, requirement-to-evidence completeness, deterministic fixtures, expected versus actual, source/downstream totals, no orphan/cycle/collision and defect severity/ownership.

## 26. Access rules

Use least-privileged test roles for each fixed principal layer plus explicit denied roles; privileged/Supreme tests are isolated, reasoned and redacted. Evidence storage itself is access-controlled. Enforce least privilege in database/service/evidence storage, not UI only.

## 27. Test data requirement

Multi-tenant/company/branch/department employee/customer/support fixtures covering all HR lifecycles, exact payroll edges, three ticket channels, typed links, malicious files, retries/races and target volumes. Include source/config versions, allowed/denied roles and reproducible checkpoint/profile.

## 28. Tests to create/update

- 20-capability × 40-anchor traceability and critical-flow suite.
- Identity/org/effective-date/time/payroll exactness and Finance handoff reconciliation.
- Ticket channel/thread/SLA/assignment/escalation/link/file isolation matrix.
- REST/GraphQL parity, jobs/retry/DLQ, migration/recovery and observability tests.
- Responsive browser/WCAG and declared target-volume performance suite.
- Unit/component/integration/API/database/migration/audit/smoke evidence proportional to risk.

## 29. Regression tests

Run all critical Platform, Commercial, Operations, Finance, Advanced TMS/WMS and Procurement tests touched by employee, customer, shipment, invoice, warehouse, vendor, user, file, job or posting contracts.

## 30. Commands to run

Run repository lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security/build gates plus relevant migration, job, import/load, failure/recovery and reconciliation commands. Never disable or suppress a gate.

## 31. Documentation to update

Integrated evidence index, traceability matrix, critical-flow results, access matrix, performance profile, migration/recovery report, defect register and HRT-294 build log. Update persistent ledgers/traceability and exact resume instructions.

## 32. Rollback/recovery note

If verification mutates test state, reset only through supported fixtures/transactions; for defects restore last trusted checkpoint, preserve evidence and give exact bounded resume. State the last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every capability and 40 anchor has current source-to-runtime evidence or an explicit blocker.
- Critical employee/time/payroll/Finance and three-channel ticket flows reconcile.
- Tenant/field/file/customer/support/link/API/job/migration/performance gates are executed without suppression.
- No unresolved critical/high blocker may advance to closure; findings are ranked and owned.
- Evidence is reconciled at one compatible checkpoint with no fabricated pass.

## 34. Definition of Done

All scoped evidence/repairs/docs, contracts, migrations if any, RLS/RBAC/field policy, APIs, UX, jobs, tests, audit, performance and rollback are complete; no critical blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; changed files/migrations/contracts; commands/results; capability/anchor or finding matrix; tenant/identity/access/privacy/payroll/Finance/ticket/link/idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-295 after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

