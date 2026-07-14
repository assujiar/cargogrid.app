# Prompt 268 — Procurement/Vendor Integrated Verification

**Prompt ID:** `CG-S11-PRC-019`  
**Package document:** `CG-AABPP-PRC-268`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-268.md`

Do not begin until every PRC-251..267 task is `VERIFIED` and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-019` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Phase 6 Quality Gate; Epic: Integrated Verification; Capability: Cross-Domain Procurement/Vendor Evidence; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Verify all 17 Phase 6 capabilities and 20 PRC anchors as one coherent extension of Platform, Commercial, Operations, Advanced TMS/WMS and Finance.

## 5. Business value

Expose broken lineage, security or financial boundaries before Phase 6 hardening and closure.

## 6. Source requirement

PRC-VND/ASM/RTE/SRC/POI-001..004, PRC-VND-US-001, FINTEST-016 and Phase 6 delivery gates. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read all persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts and Phase 6 build logs/sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, freeze the checkpoint, run feasible baselines, state plan/files and stop on evidence, tenant, vendor, security, financial, Operations or phase-boundary conflict.

## 9. Upstream dependencies

PRC-251..267 all `VERIFIED`; verified Phase 1–5 closure evidence. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-269..271. Identify affected evidence, schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 6 verification/repair/documentation paths and minimal registered defect paths authorized by WBS. Resolve repository paths; preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New unplanned capability, duplicate roots, Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, production-data mutation and hidden test/permission weakening.

## 13. Database impact

Prefer no production schema change; verify canonical vendor/rate roots, constraints, RLS, version/state/idempotency rules, sensitive-field protection, PO/contract/match equations, indexes and migration upgrade/rollback.

## 14. API impact

Verify REST/GraphQL parity, shared service/auth/field policy, contracts/cursors/errors/idempotency/concurrency and vendor/Finance/Operations handoffs. REST and GraphQL must retain one service/auth/field policy/idempotency/audit/version contract.

## 15. UI/UX impact

Verify internal procurement and enabled vendor-portal workflows, complete states, cost masking, source drilldown, responsive online-first behavior, WCAG 2.2 AA and no dead action. Include responsive/accessibility/browser evidence, complete states and no fake success/dead action.

## 16. Security impact

Adversarially verify tenant/vendor/company/branch/record/field/file/job/export/cache/realtime isolation, vendor/customer identity separation, MFA/separation, private files and support access. Preserve RLS/RBAC, server-only secrets, private scanned files, RPD-022 disclosure and evidence redaction.

## 17. Performance impact

Repeat target profiles for vendor/rate search, import, sourcing/RFQ/comparison, approval, PO/contract, capacity/assignment, scorecards, match queue, dashboard/export and portal. Record environment/dataset/concurrency, before/after plans and no-regression thresholds; no `SELECT *` or client-loaded full data.

## 18. Audit impact

Verify all privileged/sensitive/state/commitment/match actions retain actor, source/config/version, correlation/idempotency, before/after/event chain and outcome without leakage. Evidence must be useful and privacy-safe.

## 19. Data migration impact

Verify clean install and Phase 5→6 upgrade, Phase 2 vendor/rate adoption, representative backfill/reconciliation, backup/restore and rollback/forward recovery. Never edit applied migrations or fabricate history; record backup, rollback and reconciliation.

## 20. Detailed implementation tasks

- Build a 17-capability × 20-anchor evidence matrix.
- Run registration→compliance→assessment→rate→sourcing/RFQ/comparison→approval→PO/contract flow.
- Run capacity→assignment→actual cost/ePOD→vendor bill matching→AP-readiness reconciliation.
- Run PRC-VND-US-001, FINTEST-016, portal, isolation, API, migration and performance gates.
- Register every defect with source prompt, severity, reproduction, owner and invalidated evidence.

## 21. Main flow

At one recorded checkpoint, execute the complete matrix, collect machine/manual evidence, reconcile every source/handoff and mark each gate pass/fail with exact reproduction.

## 22. Alternative flow

Shard suites by dependency-clean domain or use deterministic external mocks, but keep contract tests and rerun consolidated critical flows before acceptance.

## 23. Exception flow

On failure, update error/issues ledgers, block dependent evidence and resume from the owning prompt; never silently waive a critical gate or reuse stale pass evidence. Record blocker, owner, exact reproduction and safe resume.

## 24. Business rules

- Verify exactly 17 capabilities and all 20 PRC anchors; unmapped means fail.
- Prove one canonical vendor/rate root and no duplicate shipment/resource/vendor bill/AP truth.
- Human approval governs vendor activation, selection, commitment, sensitive change and match exception.
- HR/employee Step 12, Customer Portal/Loyalty Step 13 and AI/enterprise Step 14 boundaries remain intact.
- Preserve canonical Phase 2–5 roots and source/version lineage; no duplicate truth or re-entry.
- No tenant fork, autonomous commitment, offline sync, immutable-for-all claim or partial-GA claim.

## 25. Validation rules

Every pass has command, environment, checkpoint, fixture/profile and durable evidence. Critical lifecycle, PRC-VND-US-001, FINTEST-016, isolation, exact-rate/PO/match and boundary gates must pass. Any unresolved critical/high tenant/security/vendor/financial/Operations/evidence blocker keeps the task unverified.

## 26. Access rules

Use least-privilege internal, approver, Finance, Operations and vendor roles; no superuser-only proof. Reviewers get read-only evidence access. Enforce least privilege in database/service/evidence storage, not UI only.

## 27. Test data requirement

Deterministic Tenant A/B, two vendors and customers per tenant, duplicate identities, compliance/rates/RFQs/POs/contracts/capacity/assignments/bills, edge states, retries/concurrency and target volume. Include source/config versions, allowed/denied roles and reproducible checkpoint/profile.

## 28. Tests to create/update

- 17-capability/20-anchor traceability and contract suite.
- Critical vendor-to-AP browser/API/database E2E plus PRC-VND-US-001 and FINTEST-016.
- Isolation/field/file/job/portal, idempotency/concurrency and migration/recovery tests.
- Target-volume/soak/failure/reconciliation and accessibility/browser tests.
- Unit/component/integration/API/database/migration/audit/smoke evidence proportional to risk.

## 29. Regression tests

Phase 1 identity/files/approval/jobs/APIs, Phase 2 vendor/rate/costing, Phase 3/5 assignments/cost/ePOD and Phase 4 vendor bill/AP/posting/settlement. Compare baseline/after at compatible checkpoints and explain every change.

## 30. Commands to run

Run repository lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security/build gates plus relevant migration, job/integration, import/load, failure/recovery and reconciliation commands. Never disable or suppress a gate.

## 31. Documentation to update

Traceability/evidence matrix, commands/results, defects/issues, architecture/schema/API/data flow, performance/security evidence and PRC-268 build log. Update persistent ledgers/traceability and exact resume instructions.

## 32. Rollback/recovery note

Verification does not mutate business truth; roll back any defect fix through its owner prompt, restore fixtures and rerun invalidated gates at the trusted checkpoint. State the last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- All 17 capabilities and 20 anchors have passing durable evidence.
- Critical vendor lifecycle and vendor-bill matching flows reconcile.
- Isolation, Finance/Operations compatibility and target-volume gates pass.
- Only owned non-blocking residual issues remain.
- All mandatory gates pass at one recorded checkpoint with source-to-evidence traceability.

## 34. Definition of Done

All scoped evidence/repairs/docs, contracts, migrations if any, RLS/RBAC/field policy, APIs, UX, jobs, tests, audit, performance and rollback are complete; no critical blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; changed files/migrations/contracts; commands/results; capability/anchor or finding matrix; tenant/vendor/access/Finance/Operations/idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-269 after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

