# Prompt 190 — Finance WBS and Runtime Kickoff

**Prompt ID:** `CG-S9-FIN-001`  
**Package document:** `CG-AABPP-FIN-190`  
**Version:** `0.10.0`  
**Runtime output:** `docs/build-log/phase-04/FINANCE_EXECUTION_INDEX.md`

## Objective

Create the repository-specific Phase 4 hierarchy, dependency graph, atomic task ledger and execution index without implementing Finance capabilities.

## Mandatory entry gate

Stop with `PHASE_4_BLOCKED` unless one active checkpoint proves `RUNTIME_DISCOVERY_VERIFIED`, `RUNTIME_ARCHITECTURE_VERIFIED`, `PHASE_0_VERIFIED`, `PHASE_1_VERIFIED`, `PHASE_2_VERIFIED` and `PHASE_3_VERIFIED`. Reconcile repository/branch/HEAD/worktree ownership, schema/migrations, Platform/Commercial/Operations contracts, `BillingReadinessHandoff`, actual cost, environment, baselines, unresolved errors/issues and handoff before planning.

## Required work

1. Read every persistent governance/context/status/task/change/decision/assumption/error/issues/handoff artifact and the Phase 4 sources.
2. Inspect actual repository modules, schemas, migrations, RLS/RBAC/field policy, API contracts, routes, jobs, tests, docs and commands. Never infer paths from this package.
3. Map all 24 master Finance capabilities and all 24 `FIN-*` anchors to workstream → epic → capability → feature slice → atomic implementation/verification/hardening/documentation/closure tasks.
4. Split schema, migration, policy, posting service, REST/GraphQL, UX, tests and documentation work into bounded tasks with explicit dependencies and one owner.
5. Resolve collisions, cycles, orphans and cross-phase boundaries. Record an ADR/blocker when Finance ownership, tax/legal policy, posting source, exchange-rate source, vendor master, account mapping, period, or adapter contract is ambiguous.
6. Define required evidence for balanced postings, exact decimals, idempotency, period lock, reversal, AR/AP/subledger/GL/bank reconciliation, field security and tenant isolation.
7. Map every relevant `FINTEST-001..024` scenario to an implementation or verification task; no financial-integrity scenario may be orphaned.
8. Keep full procurement/vendor lifecycle and advanced invoice matching in Step 11, full Customer Portal visibility/dispute in Step 13, and full-system finance audit in Step 15.
9. Mark only dependency-clean tasks `READY`; all others remain `NOT_STARTED` or `BLOCKED` with exact prerequisites.

## Required execution-index columns

`task_id`, `parent_prompt`, `workstream`, `epic`, `capability`, `feature_slice`, `atomic_objective`, `source_ids`, `upstream`, `downstream`, `allowed_paths`, `forbidden_paths`, `migration_ids`, `api_contracts`, `access_controls`, `financial_invariants`, `tests`, `commands`, `evidence`, `rollback`, `owner`, `status`, `resume_point`.

## Finance-specific planning gates

- A posting task cannot be `READY` before compatible chart, period, currency/rounding, tax and posting-rule versions exist.
- Invoice tasks require a verified, versioned `BillingReadinessHandoff`; AP/vendor-bill tasks require source-linked actual cost and a governed vendor reference strategy.
- Posted-state work must include normal-role immutability, reversal/adjustment, lock, idempotency and reconciliation tests together; RPD-022 absolute CRUD must remain explicitly disclosed.
- Indonesia-first tax behavior remains `BLOCKED` for activation until current SME evidence exists. Do not encode guessed legal rates.
- AI/OCR extraction tasks require human review before financial/legal posting.
- Any migration touching posted finance data requires backup, dependency analysis, reconciliation rehearsal and explicit approval.

## Completion gate

Mark kickoff `VERIFIED` only when the execution index has complete coverage, no cycle/orphan/collision, exact repository paths and commands, resolved ownership boundaries, explicit runtime gates, and a deterministic next eligible atomic task. Do not set `PHASE_4_VERIFIED`; only Prompt 218 may do that.
