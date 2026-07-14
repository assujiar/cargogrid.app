# Prompt 125 — Numbering Engine

**Prompt ID:** `CG-S6-PLT-022`  
**Package document:** `CG-AABPP-PLT-125`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-125.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-022` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Engines; Epic: Canonical Identifiers; Capability: Configurable numbering sequences; Feature slice: Tenant/org/module/date-aware atomic number allocation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement configurable collision-safe numbering with versioned formats, scopes, reservations and audit.

## 5. Business value

Generate human-readable business identifiers consistently across modules without race duplicates or hard coding.

## 6. Source requirement

PLT-CFG-001..004; numbering foundation; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Numbering schema/migrations/service/contracts/tests/docs and one representative hook. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Renumber historical records, client allocation, module-specific hard-coded formats. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Number definitions/versions/counters/reservations/allocations with tenant/scope keys, uniqueness and atomic locking.

## 14. API impact

Define/simulate/publish/next/reserve/release/status contract; generated identifier is server-only.

## 15. UI/UX impact

Format preview/config view models; full admin UI later.

## 16. Security impact

Definition/change/allocation permissions, no client-provided final numbers and tenant separation.

## 17. Performance impact

Atomic counter allocation with short locks/high concurrency and indexed scope keys.

## 18. Audit impact

Definition/version/reset/reservation/allocation/void events and source record link.

## 19. Data migration impact

Map existing sequences/last values carefully; never renumber historical records silently.

## 20. Detailed implementation tasks

1. Define format tokens, scope, reset periods, padding/prefix/suffix and lifecycle rules.
2. Implement versioned definition validation/simulation/publish and collision analysis.
3. Implement transactional allocate/reserve/release/void with concurrency/idempotency.
4. Add legacy sequence bootstrap, load tests, access/audit/docs and representative module hook.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Concurrent authorized creates receive unique sequential/scoped identifiers.

## 22. Alternative flow

Reservation/void or date/org reset follows explicit policy and preserves audit.

## 23. Exception flow

Exhausted range, invalid format, collision, stale version or transaction failure does not duplicate/reuse unsafely.

## 24. Business rules

- Internal canonical ID remains stable; display number is separate.
- Allocated numbers are not silently recycled unless explicit audited rule.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Uniqueness/scope/reset/format/idempotency and version snapshot enforced.
- Legacy counter starts above verified maximum.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Only authorized config admin changes definitions; services allocate for permitted records.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants/orgs/modules/dates, high concurrency, reset boundaries, retries, reservations/voids and legacy values. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Definition/format/simulation/version/reset/reserve/void tests.
- Concurrency/uniqueness/idempotency/RLS/RBAC/audit/load and migration tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Tenant/org/config/status, existing identifiers and future module creates.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-125.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- No duplicate or cross-scope number under concurrency/retry.
- Format/version/reset/audit/migration evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

