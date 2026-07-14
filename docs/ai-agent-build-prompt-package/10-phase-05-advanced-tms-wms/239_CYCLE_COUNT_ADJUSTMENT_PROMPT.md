# Prompt 239 — Cycle Count and Inventory Adjustment

**Prompt ID:** `CG-S10-ATW-020`  
**Package document:** `CG-AABPP-ATW-239`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-239.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-020` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Inventory Control; Epic: Inventory Accuracy; Capability: Cycle Count and Governed Adjustment; Feature slice: plan, scope/snapshot, blind count, recount, variance, approval, ledger adjustment and reconciliation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement auditable cycle counting that resolves approved variances through exact ledger movements without directly patching balances.

## 5. Business value

Improve inventory accuracy while preserving traceability, operational continuity and customer trust.

## 6. Source requirement

OPS-WMS-001..004 inventory-control slice; critical WMS E2E and RPD-022. Cite exact source sections, runtime evidence, decisions/configuration versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read all persistent context, status, task, decision, assumption, error, issue and handoff/build logs plus source requirements. Inspect inventory/warehouse code and tests, run feasible baselines, state plan/expected files, and stop on tenant/customer/data/inventory/security/financial/phase-boundary conflict.

## 9. Upstream dependencies

ATW-229..238, especially ATW-234 inventory ledger and ATW-235 tracked stock. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-240..248. Identify affected schemas, services, REST/GraphQL, warehouse tasks, reservations, reports, jobs, tests, docs and compatibility consumers.

## 11. Allowed files/folders

Use only exact Advanced WMS schema, migration, service, UI, job, test and documentation paths authorized by the WBS. Resolve paths from the repository; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate inventory roots, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes. Preserve Phase 1–4 contracts and protected decisions.

## 13. Database impact

Add count plan/scope/snapshot, assignments, blind observations, recounts, variance thresholds, approval/version, reservation/activity conflicts and idempotent inventory-adjustment movement linkage.

## 14. API impact

Shared REST/GraphQL plan/start/assign/count/recount/review/approve/reject/close/read/export operations with one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Count plan/detail, scan-first blind-count task, variance review and approval screens. Include loading, empty, error, success, permission-denied, conflict and degraded states; responsive online-first PWA, keyboard/focus/labels, scan alternatives, unsaved-change protection and no dead action.

## 16. Security impact

Warehouse/zone/bin/customer-owner/item scope; hide expected quantity during blind count; separate counter and approver where policy requires; scan IDs never bypass authorization. Preserve tenant/customer isolation, RLS, RBAC, field/record policy, server-only secrets and RPD-022 disclosure.

## 17. Performance impact

Index tenant/warehouse/plan/status/assignee/location/item/owner; generate scopes in bounded batches, use cursor lists and avoid long locks. Apply selective queries, async heavy work, limited realtime and before/after evidence; no `SELECT *` or browser-loaded full dataset.

## 18. Audit impact

Record scope/snapshot, counter, observations including zero, recount, variance, threshold/config version, approver/reason, conflicting activity and exact adjustment movement. Include correlation/idempotency key, before/after or event chain and outcome.

## 19. Data migration impact

Do not fabricate historical counts or infer unexplained adjustments; map only evidenced open counts and reconcile ledger/balance. Use additive or expand-and-contract migrations; never edit an applied migration. Rehearse backup, rollback and reconciliation.

## 20. Detailed implementation tasks

- Inspect ledger, stock identity, reservations and warehouse task contracts.
- Define count scope/snapshot/blind-count/recount/variance/approval invariants.
- Implement services/APIs, count and review UX, jobs and audit.
- Post approved differences as exact idempotent ledger movements.
- Run concurrency, scope, quantity, RLS, migration and E2E tests.

## 21. Main flow

Supervisor creates and freezes an eligible scope, assigned staff record blind observations, the system computes variance, authorized review approves within policy, and one ledger adjustment reconciles the stock identity.

## 22. Alternative flow

Schedule ABC/spot counts, allow policy-based recount, count an explicit zero, pause a conflicted location, or close a no-variance scope without adjustment.

## 23. Exception flow

Block stale snapshot, duplicate observation, changed reservation/movement, wrong owner/bin/item/lot/serial/UOM, threshold breach, self-approval violation or network ambiguity. Preserve evidence and an exact safe resume point.

## 24. Business rules

- Counts never patch or delete a balance; an approved difference creates an exact ledger movement.
- Zero is a valid observed quantity and must not be treated as missing.
- Snapshot/freeze strategy and variance/recount/approval thresholds are explicit and versioned.
- Extend canonical Phase 3/4 records; no re-entry or duplicate source of truth.
- Exact UOM/conversion/rounding and tracked-stock identity apply to every comparison.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous AI commitment, offline sync or partial-GA claim.

## 25. Validation rules

- Scope identities and expected/observed quantities use compatible UOM and snapshot versions.
- Recount and approval policy are satisfied before adjustment.
- Reject tenant/warehouse/customer-owner/item/location/config/version mismatch and stale mutation.
- Every observation, state and movement is authorized, idempotency-safe and source-reconcilable.

## 26. Access rules

Counters execute assigned scopes; supervisors plan/review; designated approvers authorize governed adjustments; customers receive only permitted read results. Enforce database/service authorization, not UI only, including export and realtime.

## 27. Test data requirement

No-variance, positive/negative variance, explicit zero, blind/recount, threshold escalation, stale snapshot, active reservation, lot/serial/expiry, duplicate retry and Tenant A/B owner fixtures with exact quantities/UOM.

## 28. Tests to create/update

- Count lifecycle/blindness/variance/recount/approval/ledger database tests.
- Inventory equation, exact-UOM, zero-count, idempotency and concurrency tests.
- RLS/RBAC/customer-owner isolation, migration, load and accessibility tests.
- Inbound→outbound critical E2E plus cycle-count correction/reconciliation.

## 29. Regression tests

Receiving, putaway, reservations, pick/pack/outbound, inventory reports, Finance billing readiness and future portal. Re-run tenant isolation, inventory integrity, API/browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration tests and build; add database reset/migration/type generation, security, target-volume WMS, inventory reconciliation and relevant E2E commands. Do not disable a gate.

## 31. Documentation to update

Count/snapshot/blindness/recount/variance/approval/adjustment contract and conflict/recovery runbook. Update persistent status/task/decision/error/issue/traceability/schema/API/data-flow/build-log artifacts and user/admin/support docs.

## 32. Rollback/recovery note

Cancel only unapproved counts; preserve approved movements and correct with a new governed movement. State trusted checkpoint, reversible steps, ledger reconciliation and exact resume command; no destructive Git/database shortcut.

## 33. Acceptance criteria

- Blind counts and policy-controlled review work end to end.
- Approved variance produces exactly one reconciling movement.
- Concurrent activity cannot silently corrupt expected or observed quantity.
- All mandatory gates pass at one recorded checkpoint with source-to-evidence traceability.

## 34. Definition of Done

No placeholder/fake persistence/dead action; migrations, types, RLS/RBAC, shared APIs, complete UX, jobs, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/security/inventory blocker remains.

## 35. Completion report format

Report IDs/checkpoint; changed files/migrations/contracts; decisions/configs; commands/results; count/variance/ledger, tenant/access, idempotency/concurrency/performance evidence; residual risks; docs; rollback/resume; next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-240 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
