# Prompt 243 — High-Volume TMS/WMS Controls

**Prompt ID:** `CG-S10-ATW-024`  
**Package document:** `CG-AABPP-ATW-243`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-243.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-024` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Operational Scale; Epic: High-Volume Reliability; Capability: TMS/WMS Throughput, Backpressure and Reconciliation Controls; Feature slice: target profiles, query/job budgets, batching, concurrency, limited realtime, observability and recovery; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Prove and harden the Phase 5 transport and warehouse workflows at declared target volumes without weakening consistency, authorization or user feedback.

## 5. Business value

Keep dispatch and warehouse operations responsive and recoverable under peak workload.

## 6. Source requirement

OPS-SHP/TMS/WMS/TRK/DOC/CST-001..004 scale slices; RPD-014/025/033/035. Cite exact source budgets, runtime evidence, environment/data profile and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, deployment topology, database/query/job/realtime/observability components, package manager/scripts, environment, baseline and trusted checkpoint.

## 8. Preconditions

Read all persistent ledgers/build logs, performance decisions and source requirements. Inspect every ATW-221..242 hot path, explain test-environment limits, establish reproducible baseline/profile and stop on correctness/security/data-integrity conflict.

## 9. Upstream dependencies

ATW-221..242. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-244..248 and all later phases consuming transport, inventory, billing or customer contracts. Identify affected queries/indexes/jobs/realtime/APIs/UI/observability/tests/docs.

## 11. Allowed files/folders

Use exact measured Advanced TMS/WMS query, index/migration, service/job, UI feedback, test/fixture, observability and documentation paths authorized by WBS. Any partition/cache addition requires evidence and rollback.

## 12. Forbidden files/folders

Speculative rewrites, unbounded cache/queue, client-loaded full datasets, global realtime fan-out, correctness/security relaxation, tenant forks, applied-migration edits, destructive cleanup, full Step 11–14 work and unrelated user changes.

## 13. Database impact

Add only measured composite/partial indexes, bounded claim/lease metadata, reconciliation checkpoints or archival/partition structures justified by plans. Preserve canonical ledger/event truth, constraints, RLS and migration safety.

## 14. API impact

Enforce server filters/sorts/search, stable cursor pagination, request/batch limits, idempotency, rate/backpressure semantics, asynchronous job receipts and REST/GraphQL parity on high-volume operations.

## 15. UI/UX impact

Keep dispatch boards and scan/task queues responsive using bounded windows, clear progress, queued/degraded/partial-data/retry states and limited realtime invalidation. Online-first responsive accessible UX; never fake completion.

## 16. Security impact

Load tests include tenant/customer isolation, scoped jobs/cursors/channels and abuse controls. Backpressure must fail safely; caches, logs, metrics and traces must not leak restricted data. Preserve RLS/RBAC and server-only secrets.

## 17. Performance impact

Define target data/concurrency profiles and budgets for p50/p95/p99 latency, throughput, queue age, error/retry rate, lock time and resource usage. Capture explain/analyze plans, before/after evidence and no-regression thresholds.

## 18. Audit impact

Record performance change/config version, dataset/profile, run/environment, job batches/attempts, throttling, dead-letter/replay, reconciliation outcome and correlation IDs without logging sensitive payloads.

## 19. Data migration impact

Rehearse online-safe indexes/partitions/retention changes at representative scale, including lock/time/disk budgets, rollback and reconciliation. Never edit applied migrations or discard business/audit evidence outside approved RPD-025 policy.

## 20. Detailed implementation tasks

- Profile all Phase 5 list/board/scan/ledger/job/integration hot paths.
- Declare representative datasets, concurrency, budgets and measurement method.
- Fix measured query/index/N+1/locking/batch/backpressure/realtime bottlenecks.
- Add durable job lease/retry/dead-letter/replay and reconciliation where needed.
- Run repeatable transport/WMS load, soak, failure and isolation tests.

## 21. Main flow

Representative concurrent dispatch and warehouse work stays within declared budgets; bounded requests and jobs apply backpressure, preserve order/idempotency, expose honest progress and reconcile all accepted work.

## 22. Alternative flow

Degrade to polling/manual refresh, queue bounded bulk operations, pause noncritical jobs, scale workers within safe lease limits or replay a reconciled dead-letter batch.

## 23. Exception flow

Fail safely on saturation, lock contention, queue lag, external throttling, worker loss, duplicate delivery, cursor invalidation or realtime disconnect. Do not drop/duplicate accepted work; expose recovery and reconcile.

## 24. Business rules

- Performance claims name environment, dataset, concurrency, commands and measured result.
- Heavy work uses PostgreSQL-backed durable jobs; realtime is limited and scoped.
- Cursor ordering is stable and scope-bound; batch/retry operations are idempotent.
- Optimization never weakens ledger equations, event order, authorization or audit.
- Partitioning/caching/materialization is evidence-driven and has invalidation/reconciliation/rollback.
- No tenant fork, autonomous AI commitment, offline sync, tamper-proof claim or partial-GA claim.

## 25. Validation rules

- Target profile and budgets are approved and reproducible.
- Accepted work count, ledger/event equations and job outcomes reconcile before/after load.
- Reject unscoped cursor/job/channel, unsafe batch size, stale lease and config mismatch.
- No critical correctness, isolation or latency regression exceeds declared threshold.

## 26. Access rules

Operational roles run normal workloads; only authorized admins trigger bulk/replay/diagnostic actions; performance data is field-filtered. Enforce database/service/job/realtime authorization, not UI only.

## 27. Test data requirement

Representative tenant/customer/warehouse/fleet/shipment/leg/task/item/lot/package/billing volumes; mixed hot/cold statuses; concurrent scanners/dispatchers; slow/failing integrations; duplicate jobs and Tenant A/B isolation probes.

## 28. Tests to create/update

- Query-plan/index/N+1/cursor stability and database-concurrency tests.
- Job lease/backpressure/retry/dead-letter/replay/idempotency/reconciliation tests.
- Dispatch board, GPS ingestion and WMS scan/load/soak tests at target profile.
- RLS/cache/channel isolation, failure recovery and browser responsiveness tests.

## 29. Regression tests

ATW-221..242 behavior, Platform/Finance contracts, audit/retention and critical transport/WMS E2Es. Compare correctness and baseline/after metrics using the same profile; record variance and environment limits.

## 30. Commands to run

Run repository lint/typecheck/test/build plus migrations, explain/analyze, load/soak/concurrency, job failure/replay, database reconciliation, security and browser-performance commands. Never bypass gates or present synthetic-only results as production proof.

## 31. Documentation to update

Target profile/budgets/results, query/index/job/realtime architecture, observability dashboards/alerts and saturation/replay/reconciliation runbooks. Update persistent ledgers, traceability, schema/API/data flow/build log and operations/support docs.

## 32. Rollback/recovery note

Disable only new optimization/config via approved switch, drain/reconcile jobs, revert compatible indexes/code safely and restore baseline behavior. Preserve accepted events and evidence; state resume command.

## 33. Acceptance criteria

- Target-volume dispatch and WMS critical flows meet declared budgets or record an explicit blocker.
- Accepted work remains exact, isolated, idempotent and reconcilable under failure.
- Boards/tasks expose honest bounded/degraded behavior.
- Before/after evidence and recovery runbooks are complete.

## 34. Definition of Done

Measured bottlenecks are resolved without placeholder/fake proof; migrations, RLS/RBAC, APIs, jobs, UX states, load/failure tests, docs, audit/observability, performance evidence and rollback are complete; no critical blocker remains.

## 35. Completion report format

Report IDs/checkpoint; profile/environment; changed files/indexes/configs; commands/results and before/after table; correctness/isolation/job/reconciliation evidence; residual limits/risks; docs; rollback/resume; next task. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-244 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
