# Prompt 138 — Platform Core Tenant and Security Hardening

**Prompt ID:** `CG-S6-PLT-035`  
**Package document:** `CG-AABPP-PLT-138`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-138.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-035` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Phase Hardening; Epic: Platform Risk Reduction; Capability: Close integrated Platform Core blockers; Feature slice: Evidence-ranked tenant/security/data/platform repairs; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Close PLT-137 findings through atomic root-cause repairs and re-verification without adding new capability.

## 5. Business value

Meet Phase 2 entry threshold with trustworthy isolation, engines, APIs, jobs, files and portals.

## 6. Source requirement

PLT-137 report; threat/debt/error/issues registers; accepted-risk controls. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Exact finding-linked source/config/schema/tests/docs approved by hardening plan. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

New domain capability, unrelated debt/refactor, production mutation, gate suppression. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Only finding-linked additive repair migrations with rebuild/upgrade/RLS/data preservation.

## 14. API impact

Repair existing parity/access/validation/performance only; no new endpoints.

## 15. UI/UX impact

Repair existing states/accessibility/performance only; no redesign/new page.

## 16. Security impact

Prioritize critical/high tenant, access, secret, file, support, key/webhook and admin risks.

## 17. Performance impact

Fix measured regressions with before/after; no speculative tuning.

## 18. Audit impact

Finding→root cause→repair→test→closure/residual links and Supreme disclosure.

## 19. Data migration impact

Any data repair idempotent/reconciled/separately checkpointed.

## 20. Detailed implementation tasks

1. Rank PLT-137 findings and split exact atomic repair tasks.
2. Implement only authorized root-cause repairs within exact paths.
3. Run failing-before/passing-after negatives and affected/full integrated gates.
4. Reconcile issues/risks/docs and repeat PLT-137 until mandatory blockers close.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Every critical/high Platform Core blocker closes with reproducible evidence.

## 22. Alternative flow

Non-critical residual risk has authorized owner/expiry/monitoring without violating Phase 2 gate.

## 23. Exception flow

Unknown root cause/untrusted DB/unsafe migration/scope expansion blocks and invokes recovery.

## 24. Business rules

- No new feature/cosmetic cleanup or test/control weakening.
- Critical tenant/security/data defect cannot be accepted.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Every change maps to one finding and no unrelated file/contract change.
- Integrated checkpoint/schema remains trusted.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Repairs preserve/strengthen four-layer least privilege and isolation.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Exact synthetic reproducers plus full two-tenant Platform Core fixtures. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Finding-specific negative/regression and affected integration tests.
- Full tenant/access/migration/API/job/file/portal/performance gates.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- All PLT-105..137 verified behavior and Phase 0 foundations.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-138.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- All mandatory blockers close and PLT-137 re-passes.
- Residual risks non-critical, authorized and visible.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

