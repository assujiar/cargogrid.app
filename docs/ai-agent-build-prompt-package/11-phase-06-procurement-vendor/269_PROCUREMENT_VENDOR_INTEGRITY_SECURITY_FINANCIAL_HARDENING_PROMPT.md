# Prompt 269 — Procurement/Vendor Integrity, Security and Financial Hardening

**Prompt ID:** `CG-S11-PRC-020`  
**Package document:** `CG-AABPP-PRC-269`  
**Version:** `0.12.0`  
**Runtime build log:** `docs/build-log/phase-06/PRC-269.md`

Do not begin until PRC-268 is `VERIFIED`, its findings are triaged, and `PHASE_5_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S11-PRC-020` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 6 — Procurement and Vendor Management`; package `0.12.0`.

## 3. Workstream

Workstream: Phase 6 Assurance; Epic: Findings Remediation; Capability: Vendor, Commitment and Match Boundary Hardening; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Repair every Phase 6 blocking finding and adversarially reverify vendor identity, sensitive data, commitments, assignment and Finance boundaries without adding scope.

## 5. Business value

Reduce vendor fraud, data leakage, invalid assignment, duplicate commitment and AP mismatch risk.

## 6. Source requirement

PRC-268 findings plus all Phase 6 OPS/RPD controls, especially RPD-014/016/022/023/025/032/033/038/039. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read all persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts and Phase 6 build logs/sources. Inspect actual code/schema/policies/APIs/UI/jobs/tests, freeze the checkpoint, run feasible baselines, state plan/files and stop on evidence, tenant, vendor, security, financial, Operations or phase-boundary conflict.

## 9. Upstream dependencies

PRC-268 `VERIFIED` with findings triaged and assigned. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

PRC-270..271. Identify affected evidence, schemas, services, REST/GraphQL, jobs/integrations/files, Operations/Finance consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 6 verification/repair/documentation paths and minimal registered defect paths authorized by WBS. Resolve repository paths; preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New unplanned capability, duplicate roots, Step 12–14 implementation, tenant forks, applied-migration edits, destructive cleanup, production-data mutation and hidden test/permission weakening.

## 13. Database impact

Harden only finding-backed constraints, RLS/field policies, encryption/masking, idempotency/version/state transitions, PO/match equations, job leases and measured indexes using safe migrations.

## 14. API impact

Repair shared authorization/field parity, validation/enumeration, idempotency/concurrency, cursors/rate limits, external tokens/callbacks and Finance/Operations failure semantics compatibly. REST and GraphQL must retain one service/auth/field policy/idempotency/audit/version contract.

## 15. UI/UX impact

Repair unsafe/misleading actions, stale/conflict handling, masking/reveal, approval/override warnings, portal isolation, recovery messaging and accessibility without fake success. Include responsive/accessibility/browser evidence, complete states and no fake success/dead action.

## 16. Security impact

Test duplicate vendor abuse, bank/tax change fraud, document malware/access, competitor offer leakage, forged vendor tokens, approval bypass, PO tampering, match/payment confusion and support misuse. Preserve RLS/RBAC, server-only secrets, private scanned files, RPD-022 disclosure and evidence redaction.

## 17. Performance impact

Rerun affected target-volume queries/jobs/portal flows and reconciliation; hardening cannot regress declared budgets or introduce unsafe bypass. Record environment/dataset/concurrency, before/after plans and no-regression thresholds; no `SELECT *` or client-loaded full data.

## 18. Audit impact

Ensure repaired actions retain actor, purpose, source/config/version, MFA/separation, correlation/idempotency, before/after/event chain, denial/failure and override evidence. Evidence must be useful and privacy-safe.

## 19. Data migration impact

Rehearse repair migrations on clean install and Phase 5→6 upgrade with lock/time/disk budgets, key/backup recovery, rollback and vendor/rate/PO/match reconciliation. Never edit applied migrations or fabricate history; record backup, rollback and reconciliation.

## 20. Detailed implementation tasks

- Reproduce and rank every PRC-268 finding/root cause.
- Implement the minimal schema/policy/service/UI/job/docs repair and failing-then-passing regression.
- Run adversarial vendor identity, field/file/portal, commitment, assignment and match tests.
- Rerun affected focused plus complete critical integrated/non-regression gates.
- Close findings only with durable before/after evidence and document residual risk.

## 21. Main flow

For each registered finding, reproduce at the frozen checkpoint, apply a bounded repair, prove focused regression, rerun impacted integration gates and close with reviewer evidence.

## 22. Alternative flow

If a safe fix cannot land, disable only the affected optional/reversible surface through approved control and keep closure blocked when any mandatory capability is impacted.

## 23. Exception flow

Stop on data-loss/key risk, ambiguous ownership, new product decision, incompatible contract, unreconciled source/Finance state, critical regression or evidence mismatch. Record blocker, owner, exact reproduction and safe resume.

## 24. Business rules

- Every change maps to a PRC-268 finding and adds a regression test.
- Authorization and vendor/rate/PO/match invariants are server/database enforced where applicable.
- Fixes preserve canonical roots, source snapshots and Finance/Operations ownership.
- RPD-022 remains disclosed; do not claim universal immutability or non-repudiation.
- Preserve canonical Phase 2–5 roots and source/version lineage; no duplicate truth or re-entry.
- No tenant fork, autonomous commitment, offline sync, immutable-for-all claim or partial-GA claim.

## 25. Validation rules

Before evidence reproduces and after evidence disproves the same defect; affected focused/integrated/Phase 1–5 regression gates, migration/API compatibility and reconciliation pass. Any unresolved critical/high tenant/security/vendor/financial/Operations/evidence blocker keeps the task unverified.

## 26. Access rules

Use least-privilege roles/fixtures; only authorized maintainers change security, keys, policies or migrations, with reviewer/separation evidence. Enforce least privilege in database/service/evidence storage, not UI only.

## 27. Test data requirement

Reuse PRC-268 fixtures plus minimal exploit/concurrency/failure cases for each finding: duplicate identities, bank/tax fraud, forged tokens, unsafe files, stale approvals, duplicate jobs and external failures. Include source/config versions, allowed/denied roles and reproducible checkpoint/profile.

## 28. Tests to create/update

- One targeted failing-then-passing regression per finding.
- Adversarial RLS/RBAC/field/file/job/portal/integration tests.
- Vendor/rate/PO/assignment/match/idempotency/concurrency/migration/recovery tests.
- Full critical vendor-to-AP E2E and affected target-volume profiles.
- Unit/component/integration/API/database/migration/audit/smoke evidence proportional to risk.

## 29. Regression tests

All PRC-251..268 suites and impacted Phase 1–5 gates; no test deletion, snapshot relaxation or permission broadening. Compare baseline/after at compatible checkpoints and explain every change.

## 30. Commands to run

Run repository lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security/build gates plus relevant migration, job/integration, import/load, failure/recovery and reconciliation commands. Never disable or suppress a gate.

## 31. Documentation to update

Finding root cause/change/evidence/closure, threat model, sensitive-field/key/file controls, integrity architecture, runbooks, known risks and PRC-269 log. Update persistent ledgers/traceability and exact resume instructions.

## 32. Rollback/recovery note

Each repair has reversible code/config/data/key plan; preserve commitments/Finance receipts/audit, reconcile all sources and rerun invalidated gates. State the last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every blocking PRC-268 finding is reproducibly fixed.
- Vendor isolation, sensitive fields, commitments and Finance boundaries pass adversarial tests.
- Critical flows and performance do not regress.
- Residual risks are explicit, owned and non-blocking.
- All mandatory gates pass at one recorded checkpoint with source-to-evidence traceability.

## 34. Definition of Done

All scoped evidence/repairs/docs, contracts, migrations if any, RLS/RBAC/field policy, APIs, UX, jobs, tests, audit, performance and rollback are complete; no critical blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; changed files/migrations/contracts; commands/results; capability/anchor or finding matrix; tenant/vendor/access/Finance/Operations/idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release PRC-270 after this task is `VERIFIED`. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do so.

