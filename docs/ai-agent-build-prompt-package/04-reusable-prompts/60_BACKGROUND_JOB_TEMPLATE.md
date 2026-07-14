# Template 60 — Background Job

**Prompt ID:** `CG-S4-REUSE-008`  
**Package document:** `CG-AABPP-REUSE-060`  
**Version:** `0.5.0`  
**Intended use:** Implement one durable asynchronous job using the PostgreSQL queue foundation.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Background Jobs and Automation.

## 4. Objective

Implement {{JOB_TYPE}} with tenant context, idempotency, retry, DLQ, progress, cancellation and result evidence.

## 5. Business value

Process heavy/reliable work without blocking requests or losing/duplicating business effects.

## 6. Source requirement

{{JOB_REQUIREMENT_IDS}}, {{QUEUE_CONTRACT_ID}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`, approved ADRs/migrations/contracts, verified runtime gates and baseline evidence. All must be satisfied or explicitly blocking.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; normally 5–15 files, one module boundary and at most 1–3 approved migrations. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, lockfiles unless dependency scope is explicit, secrets, generated artifacts unless authorized, tenant data, and broad refactors.

## 13. Database impact

Use queue/job tables with tenant keys, atomic claim/lock, status transitions, attempts, idempotency, progress/result and retention indexes.

## 14. API impact

Define enqueue/status/cancel/result contracts and authorization; request path must not perform heavy work synchronously.

## 15. UI/UX impact

If surfaced, provide queued/running/progress/success/failed/cancelled/retry states and accessible feedback.

## 16. Security impact

Persist minimum safe payload; server-only execution; tenant/record re-authorization and secret redaction.

## 17. Performance impact

Bound batch/concurrency, lock duration, polling, payload, timeout and retry storm; define worker-separation thresholds.

## 18. Audit impact

Audit enqueue, claim, attempt, retry, cancel, completion, DLQ/replay and privileged manual actions.

## 19. Data migration impact

Any queue schema change uses migration template; job payload versioning supports in-flight compatibility.

## 20. Detailed implementation tasks

1. Define payload/result schema, dedupe key, state machine and ownership.
2. Implement transactional enqueue/claim, lease/heartbeat, retry/backoff/jitter, timeout, cancellation, progress, DLQ and replay.
3. Make business side effects idempotent and reconcile partial external/database effects.
4. Add metrics/alerts/runbook, retention/cleanup and threshold-based capacity plan.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Authorized enqueue produces one effective result and a traceable terminal state.

## 22. Alternative flow

Duplicate enqueue returns/reuses the prior result; cancellation or retry follows allowed states.

## 23. Exception flow

Worker crash, lease expiry, timeout, poison payload, partial effect, dependency outage and DLQ replay recover safely.

## 24. Business rules

- PostgreSQL durable queue is the initial architecture; separate workers are threshold-driven.
- Retries may repeat execution but never duplicate effective business impact.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- State transitions, attempt limits, leases and payload versions are enforced.
- Cancellation distinguishes not-started, cooperative in-progress and irreversible effects.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Enqueue/status/result/cancel/replay require tenant, role/scope and record authorization.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Two tenants, duplicate keys, slow/crashing workers, transient/permanent failures, cancellation, stale lease and poison payload. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Queue state/locking/concurrency/idempotency/retry/DLQ/cancel/replay tests.
- Cross-tenant, auth, partial-effect reconciliation, retention and throughput tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Request latency, existing jobs, database contention, monitoring and business transaction flows.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Job reaches correct terminal states with exactly-once effective behavior.
- Failure, retry, DLQ, cancellation, audit and performance evidence passes.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
