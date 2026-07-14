# Prompt 28 — Performance Baseline

**Prompt ID:** `CG-S2-DISC-008`  
**Package document:** `CG-AABPP-DISC-028`  
**Version:** `0.3.0`  
**Parent:** Step 2 — Repository Discovery and Baseline  
**Runtime output:** `docs/discovery/08_PERFORMANCE_BASELINE.md`

## Objective

Establish a reproducible performance baseline from repository evidence and existing safe tooling, without changing code, dependencies, configuration, data, or production-linked services.

## Source requirements

- Master Prompt §§11, 15–16 and Step 2.
- Technical Architecture §§7–8, 25, 27–33.
- Delivery Plan §§16–18, 21.
- RPD-004/005/019/020/026/028/036/039.

## Preconditions and guardrails

Prompts 21–27 are complete at one checkpoint. Use only already-installed tools and isolated/local or synthetic data. Do not install dependencies, run load tests against shared/production systems, mutate data, tune code, create indexes, change caching, or present inferred targets as measured results.

Every result must identify environment, exact redacted command, start/end time, duration, exit code, dataset size, concurrency, warm/cold state, and worktree state. Unsafe or unavailable tests are `NOT_RUN` with reason.

## Required tasks

1. Inventory build outputs, route bundles, server/client boundaries, rendering mode, source maps, compression, asset strategy, caching, revalidation, realtime subscriptions, and known budgets.
2. Inspect query paths for unbounded reads, `SELECT *`, N+1 patterns, missing pagination, broad joins, repeated aggregations, full-dataset exports, and live-OLTP dashboard pressure.
3. Correlate database indexes and safe existing query-plan evidence with critical tenant, finance, shipment, inventory, search, report, and dashboard paths.
4. Inventory API latency instrumentation for REST and GraphQL, including query complexity/depth, payload size, batching, timeout, cancellation, and pagination controls.
5. Assess job throughput, retry/backoff, locking, idempotency, DLQ, report/export generation, file scanning, signed delivery, and cleanup paths.
6. Run only existing safe build/analyze/benchmark commands. Preserve raw outputs and do not regenerate committed artifacts.
7. Separate `MEASURED`, `STATIC_FINDING`, `INFERRED`, and `NOT_RUN` evidence. Derive thresholds only from ratified requirements or recorded tests.
8. Identify bottlenecks, measurement blind spots, direct-GA risks, and prerequisites for a later representative load test.

## Required output

Write `docs/discovery/08_PERFORMANCE_BASELINE.md` containing:

- checkpoint and environment;
- applicable budgets/targets with source;
- command/result ledger;
- route and bundle findings;
- database/query evidence;
- REST/GraphQL findings;
- job/report/file findings;
- live-dashboard guard assessment;
- bottlenecks and ranked risks;
- baseline trust: `GREEN`, `AMBER`, `RED`, or `UNKNOWN`;
- missing evidence and safe follow-up tasks.

## Completion gate

Complete only when all claims are evidence-classified, no shared/production load was generated, the worktree is reconciled, and the output references the same checkpoint as Prompts 21–27.
