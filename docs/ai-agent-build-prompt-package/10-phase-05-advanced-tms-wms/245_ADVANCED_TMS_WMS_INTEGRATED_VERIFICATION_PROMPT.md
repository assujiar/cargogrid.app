# Prompt 245 — Advanced TMS/WMS Integrated Verification

**Prompt ID:** `CG-S10-ATW-026`  
**Package document:** `CG-AABPP-ATW-245`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-245.md`

Do not begin until all ATW-221..244 tasks are `VERIFIED` and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-026` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Phase 5 Quality Gate; Epic: Integrated Verification; Capability: Cross-Domain TMS/WMS Evidence; Feature slice: requirements, transport/WMS E2E, isolation, finance/integration compatibility, performance and reconciliation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Verify all 24 Phase 5 capabilities as one coherent extension of the Phase 3/4 platform and expose every remaining blocker before hardening.

## 5. Business value

Prevent locally passing features from masking broken transport, inventory, customer or Finance outcomes.

## 6. Source requirement

All advanced slices of OPS-SHP/TMS/WMS/TRK/DOC/CST-001..004, OPS-WMS-US-001 and Phase 5 TMS/WMS gates. Cite exact sources and evidence for every result.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, deployment/test topology, schemas/contracts/routes/modules/jobs/integrations, package scripts, environment, baselines and trusted checkpoint.

## 8. Preconditions

Read all persistent ledgers, ATW-221..244 build logs, source requirements, decisions and Phase 3/4 closure evidence. Confirm prerequisites `VERIFIED`, freeze the tested checkpoint, declare environment/data/limitations and stop if evidence is missing or inconsistent.

## 9. Upstream dependencies

ATW-221..244 and verified Phase 3/4 platform and Finance closures.

## 10. Downstream impact

ATW-246..248. Findings must map to exact owners/files/contracts/tests and block closure until repaired and reverified.

## 11. Allowed files/folders

Verification tests/fixtures/scripts, evidence/build logs and minimal defect fixes explicitly registered in the task ledger. A defect fix must identify source prompt and rerun all impacted gates.

## 12. Forbidden files/folders

New unplanned capability, full Step 11–14 scope, tenant fork, duplicate roots, test/permission weakening, production-data mutation, destructive cleanup, applied-migration edits and unrelated user changes.

## 13. Database impact

Prefer none beyond test fixtures and approved defect migrations. Verify canonical root extension, constraints, RLS, ledger equations, state/version/idempotency invariants, indexes and migration upgrade/rollback behavior.

## 14. API impact

Verify REST/GraphQL parity, shared service/auth/field policy, contract compatibility, cursor/idempotency/concurrency/errors, integration callbacks/jobs and no unauthorized resource enumeration.

## 15. UI/UX impact

Verify responsive online-first dispatcher/warehouse/customer-contract surfaces, scan alternatives, keyboard/focus/labels, all loading/empty/error/success/denied/conflict/degraded states, unsaved changes and no dead action.

## 16. Security impact

Verify tenant/customer/company/branch/warehouse/owner/record/field/file/job/realtime isolation, RLS/RBAC, authorization on scan/reference IDs, private scanned files/signed URLs, server-only secrets and RPD-022 disclosures.

## 17. Performance impact

Repeat target-volume Phase 5 profiles and budgets for queries, boards, scans, ledger, jobs, telemetry and billing/case queues. Compare baseline/after and validate backpressure, limited realtime and reconciliation.

## 18. Audit impact

Verify every privileged/state/movement/decision/handoff action carries actor/context, source/config version, correlation/idempotency, before/after or event chain and outcome; evidence must be useful without leaking restricted fields.

## 19. Data migration impact

Verify clean install and Phase 4→5 upgrade, representative backfill/reconciliation, backup/restore and rollback/forward-recovery. Never fabricate history or edit applied migrations.

## 20. Detailed implementation tasks

- Build a 24-capability × 24-advanced-anchor evidence matrix.
- Run transport multi-leg→dispatch→telemetry→milestones→delivery/claim scenarios.
- Run inbound→receiving→putaway→ledger→pick→pack→outbound critical WMS E2E.
- Verify cycle count, labels, billing, customer access and high-volume controls.
- Run isolation/security/API/migration/performance/recovery gates and register defects.

## 21. Main flow

At one immutable recorded checkpoint, execute the full matrix, collect machine/manual evidence, reconcile transport/inventory/Finance outcomes and mark each gate pass/fail with exact reproduction.

## 22. Alternative flow

Shard suites by dependency-clean domain or use deterministic mocks for unavailable external providers, but retain contract tests and clearly label non-production limitations; rerun consolidated critical gates before acceptance.

## 23. Exception flow

On failure, record `ERROR_LEDGER`/`KNOWN_ISSUES`, severity, owner, source prompt, reproduction, evidence and safe resume; invalidate dependent passes after a code/schema/config change and never waive a critical gate silently.

## 24. Business rules

- Verify exactly 24 capabilities and all 24 OPS advanced anchors; unmapped means fail.
- Prove canonical Phase 3/4 root extension and no duplicate shipment/inventory/customer/Finance truth.
- Stock equations, transport event order, custody and Finance receipts reconcile exactly.
- Full vendor/PO/compliance/rate lifecycle, HR/payroll, full Customer Portal and AI depth remain Steps 11–14.
- Claims and route recommendations remain human-governed; no false optimum/autonomous commitment.
- No tenant fork, offline sync, immutable-for-all claim or pilot/partial-GA claim.

## 25. Validation rules

- Each pass has command, environment, checkpoint, fixture/data profile and durable evidence.
- Critical WMS E2E, OPS-WMS-US-001 and Phase 5 scan/task/ledger/load/integration gates all pass.
- Tenant/customer isolation, exact inventory and REST/GraphQL parity have negative tests.
- Any unresolved critical/high correctness, security, inventory or financial defect blocks verification.

## 26. Access rules

Use dedicated test roles for every allowed/denied matrix; no superuser-only proof. Production-like files/jobs/integrations remain isolated. Reviewers need read-only evidence access; fixes follow normal least privilege.

## 27. Test data requirement

Deterministic Tenant A/B companies/customers/warehouses/owners, multi-leg multimodal shipments, fleets/drivers, telemetry, inbound/outbound stock with lot/serial/expiry, bills/claims, edge states, concurrency/retries and target-volume fixtures.

## 28. Tests to create/update

- 24-capability traceability and contract suite.
- Transport and critical WMS browser/API/database E2Es.
- Isolation/field/file/job/realtime, idempotency/concurrency and migration/recovery tests.
- Target-volume/soak/failure/reconciliation and accessibility tests.

## 29. Regression tests

Re-run Phase 1–4 critical closures, Platform auth/scoping, Finance contracts and all ATW-221..244 focused suites. Compare one before/after baseline and explain every failure/change.

## 30. Commands to run

Run repository lint/typecheck/unit/integration/database/API/contract/browser/accessibility/security/build gates plus clean-install/upgrade/rollback, target-volume/soak/failure, job/integration and reconciliation commands. Never disable gates.

## 31. Documentation to update

Traceability/evidence matrix, gate results, errors/issues, test/runbook/architecture/data-flow/API/schema and ATW-245 build log. Record external limitations, manual evidence and exact resume for failures.

## 32. Rollback/recovery note

Verification itself does not mutate business data. Roll back defect fixes per their source prompt, restore fixtures/environment, reconcile jobs/ledgers and rerun invalidated gates from the trusted checkpoint.

## 33. Acceptance criteria

- All 24 capabilities and 24 advanced anchors have passing durable evidence.
- Critical transport/WMS, isolation, Finance compatibility and target-volume gates pass.
- Phase boundaries and non-regression are proven.
- Every remaining issue is non-blocking, owned and documented.

## 34. Definition of Done

The integrated evidence matrix is complete at one checkpoint; all mandatory automated/manual gates pass; defect fixes are traceable/retested; no critical tenant/security/inventory/financial/operations blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; 24×24 matrix; commands/results; E2E/isolation/API/migration/performance/reconciliation evidence; defect list and retests; limitations; docs; rollback/resume; recommendation for ATW-246. Update all ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-246 after ATW-245 is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
