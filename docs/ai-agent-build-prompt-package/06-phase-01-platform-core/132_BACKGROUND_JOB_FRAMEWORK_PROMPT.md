# Prompt 132 — Background Job Framework

**Prompt ID:** `CG-S6-PLT-029`  
**Package document:** `CG-AABPP-PLT-132`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-132.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-029` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Runtime; Epic: Durable Asynchronous Processing; Capability: PostgreSQL job queue; Feature slice: Enqueue→claim→execute→retry/DLQ/cancel/result; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement PostgreSQL-backed durable job framework with tenant context, idempotency, leases, retry/DLQ, progress, cancellation and observability.

## 5. Business value

Run heavy/reliable work without request blocking or duplicate business effects.

## 6. Source requirement

PKG-PLT-JOB-001; RPD queue decision; job architecture; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Job queue schema/migrations/service/worker/contracts/tests/docs/runbook and isolated example. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

External queue replacement, unmeasured worker split, domain batch implementation. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Job/type/payload-version/state/attempt/lease/progress/result/idempotency/DLQ/retention tables with RLS/indexes/atomic claim.

## 14. API impact

Authorized enqueue/status/cancel/result/retry/replay contracts.

## 15. UI/UX impact

Reusable progress/terminal/retry states; no business job page.

## 16. Security impact

Minimum classified payload, server workers, tenant/record re-authorization, no secrets in payload/logs.

## 17. Performance impact

Bound concurrency/batches/poll/locks/timeout/backoff; worker separation only at measured thresholds.

## 18. Audit impact

Enqueue/claim/attempt/retry/cancel/complete/DLQ/replay/manual operations.

## 19. Data migration impact

In-flight payload versions and schema compatibility; no unsafe loss of queued jobs.

## 20. Detailed implementation tasks

1. Define job type/payload/result/version/state/lease/idempotency/cancellation contracts.
2. Implement transactional enqueue/claim/heartbeat/complete/fail with retry/backoff/jitter/DLQ.
3. Implement progress/cancel/result/replay/retention and exactly-once effective side-effect guidance.
4. Add worker runner, observability/alerts/runbook, concurrency/failure/load/tests/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized job is claimed and produces one effective terminal result.

## 22. Alternative flow

Duplicate enqueue reuses prior result; transient failure retries; cancellation follows state.

## 23. Exception flow

Worker crash/stale lease/poison payload/timeout/partial effect enters safe retry/DLQ/reconciliation.

## 24. Business rules

- PostgreSQL queue is initial standard; separate workers require measured threshold ADR.
- At-least-once execution must yield idempotent effective behavior.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- State/lease/attempt/version/idempotency/cancel transitions DB-enforced.
- No two live workers own same lease/effective side effect.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Tenant/RBAC/record checks for enqueue/status/result/cancel/replay; workers least privilege.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, duplicates, concurrent workers, stale leases, crashes, transient/permanent failures, cancellation and poison payload. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Queue state/claim/lease/concurrency/idempotency/retry/DLQ/cancel/replay/retention tests.
- RLS/RBAC/cross-tenant/partial-effect/audit/load/worker recovery tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Database contention, request latency, notifications/import-export/files and observability.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-132.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Jobs are durable/recoverable with one effective outcome and tenant isolation.
- Retry/DLQ/cancel/load/runbook evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

