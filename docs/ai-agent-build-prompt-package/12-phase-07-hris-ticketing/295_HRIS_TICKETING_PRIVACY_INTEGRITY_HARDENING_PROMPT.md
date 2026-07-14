# Prompt 295 — HRIS and Ticketing Privacy, Integrity and Service Hardening

**Prompt ID:** `CG-S12-HRT-023`  
**Package document:** `CG-AABPP-HRT-295`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-295.md`

Do not begin until all upstream tasks are `VERIFIED` and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-023` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Integrated Verification, Hardening, Documentation and Closure; Epic: Phase 7 Evidence Closure; Capability: Evidence-Ranked Defect Repair and Reverification; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Repair the smallest evidence-ranked set of Phase 7 integrity, privacy, security, service, performance and recovery defects, then reverify affected and regression gates.

## 5. Business value

Close real risk before handoff without using a broad cleanup or weakening tests, controls or product boundaries.

## 6. Source requirement

HRT-294 evidence plus all Phase 7 requirements and ratified RPD controls. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-294 VERIFIED with finding register. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-296..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 verification, repair, test, evidence and documentation paths authorized by WBS. Resolve repository paths; preserve unrelated user-owned changes.

## 12. Forbidden files/folders

New unplanned capability, duplicate roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, production mutation and hidden test/permission weakening.

## 13. Database impact

Only bounded additive/expand-contract fixes tied to registered findings: constraints, RLS, field policies, effective versions, exact calculations, ticket visibility/SLA/link integrity or indexes. No speculative redesign.

## 14. API impact

Repair shared-service REST/GraphQL parity, projection, idempotency, errors, rate limit, job/handoff semantics only where HRT-294 proves a defect; update contracts and consumers together. REST and GraphQL retain one service/auth/field policy/idempotency/audit/version contract.

## 15. UI/UX impact

Repair verified accessibility/state/masking/thread/action defects without cosmetic redesign or pulling Step 13/14 features forward. Preserve responsive/accessibility evidence, complete states and no fake success/dead action.

## 16. Security impact

Prioritize cross-tenant/customer/support/field/file/link leaks, payroll exposure, missing MFA/separation, unsafe logs/cache/search/export, unscanned files and RPD-022 misclaims. Preserve RLS/RBAC, server-only secrets, private scanned files, field policy, RPD-022 disclosure and evidence redaction.

## 17. Performance impact

Fix measured query/job/thread/payroll/SLA/export regressions with before/after plans, environment/profile and no-regression thresholds; no blind caching or denormalization. Record before/after or verification profile and no-regression threshold; no `SELECT *` or client-loaded full data.

## 18. Audit impact

Repair missing/unsafe audit events, source/config/correlation chain, denial evidence or raw sensitive telemetry; keep evidence privacy-safe and retrievable. Evidence must be useful, source-linked and privacy-safe.

## 19. Data migration impact

Every fix has clean/upgrade/rollback/restore rehearsal and source/downstream reconciliation; applied migrations stay untouched. Never edit applied migrations or fabricate history; record backup, rollback and reconciliation.

## 20. Detailed implementation tasks

- Triage HRT-294 findings by exploitability, integrity, payroll, service, scale and recovery impact.
- Create one bounded WBS task per independent repair with exact tests and rollback.
- Implement highest-severity authorized repairs without scope expansion.
- Re-run targeted, abuse, migration, performance and full affected regression suites.
- Update finding state/evidence and block handoff on unresolved critical/high defects.

## 21. Main flow

Select the highest-ranked reproducible finding, freeze baseline, implement the minimum root-cause repair, execute targeted and regression evidence, reconcile side effects and close or return the finding with exact state.

## 22. Alternative flow

Accept only non-critical residual risk through authorized governance with owner, rationale, expiry/trigger and visible closure impact; otherwise defer with Phase 7 blocked.

## 23. Exception flow

If repair expands scope, conflicts with user-owned changes, needs new authority or cannot preserve data, stop and escalate. Never bypass RLS, field policy, exact calculation, MFA, scan, tests or phase boundary. Record blocker, owner, exact reproduction and safe resume.

## 24. Business rules

- One repair task addresses one coherent root cause and references HRT-294 evidence.
- Critical/high tenant, sensitive-data, payroll/Finance, customer/support or linked-record defects cannot be accepted for Phase 7 closure.
- Performance changes require measured benefit and integrity/privacy parity.
- No test deletion, permission broadening, fake evidence, tenant fork or destructive migration.
- RPD-022 residual risk is disclosed, not 'fixed' through false immutability claims.

## 25. Validation rules

Each finding has reproduction, root cause, affected scope, owner, fix, exact tests, before/after evidence, migration/rollback and closure verdict at one checkpoint.

## 26. Access rules

Use least privilege for repair and tests; privileged access is reasoned/time-bound/audited. Repair must preserve or narrow permissions across every REST/GraphQL/job/file/search/export surface. Enforce least privilege in database/service/evidence storage, not UI only.

## 27. Test data requirement

Reuse HRT-294 deterministic fixtures and add the smallest failing cases, boundary/race/retry/volume data and Tenant A/B/customer/support roles needed to prove the root cause. Include source/config versions, allowed/denied roles and reproducible checkpoint/profile.

## 28. Tests to create/update

- Finding-specific failing-before/passing-after tests.
- Tenant/field/file/payroll/customer/support/link abuse regression.
- Exact time/payroll/SLA/idempotency/concurrency/reconciliation regression.
- Clean/upgrade/rollback/recovery and observability evidence.
- Affected browser/accessibility/performance and full critical-flow smoke.
- Unit/component/integration/API/database/migration/audit/smoke evidence proportional to risk.

## 29. Regression tests

All HRT-294 critical suites and every Phase 1–6 contract touched by the repair; compare compatible baseline/after and explain every variance.

## 30. Commands to run

Run repository lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security/build gates plus relevant migration, job, import/load, failure/recovery and reconciliation commands. Never disable or suppress a gate.

## 31. Documentation to update

Finding/root-cause register, ADR if needed, schema/API/data-flow/security/performance changes, test evidence, operator runbook and HRT-295 build log. Update persistent ledgers/traceability and exact resume instructions.

## 32. Rollback/recovery note

Revert only the bounded repair using rehearsed compatible path, preserve newly captured evidence/data, restore last trusted behavior and reopen the finding with exact resume. State the last trusted checkpoint and never use destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every HRT-294 critical/high finding is fixed and reverified; none is hidden or downgraded without evidence.
- Permissions, exact calculations, ticket visibility and Finance/source reconciliation are not weakened.
- Migration/recovery, browser/accessibility and measured performance regressions pass.
- Remaining non-critical risks have authorized owner, trigger/expiry and closure treatment.
- Evidence is reconciled at one compatible checkpoint with no fabricated pass.

## 34. Definition of Done

All scoped evidence/repairs/docs, contracts, migrations if any, RLS/RBAC/field policy, APIs, UX, jobs, tests, audit, performance and rollback are complete; no critical blocker remains.

## 35. Completion report format

Report IDs/checkpoint/environment; changed files/migrations/contracts; commands/results; capability/anchor or finding matrix; tenant/identity/access/privacy/payroll/Finance/ticket/link/idempotency/reconciliation/performance evidence; residual risks; docs; rollback/resume; next recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-296 after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

