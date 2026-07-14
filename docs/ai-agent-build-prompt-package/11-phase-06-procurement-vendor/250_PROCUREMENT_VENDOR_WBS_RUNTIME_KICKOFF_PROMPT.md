# Prompt 250 — Procurement/Vendor WBS and Runtime Kickoff

**Prompt ID:** `CG-S11-PRC-001`  
**Package document:** `CG-AABPP-PRC-250`  
**Version:** `0.12.0`  
**Runtime output:** `docs/build-log/phase-06/PROCUREMENT_VENDOR_EXECUTION_INDEX.md`

## Objective

Create the repository-specific Phase 6 hierarchy, dependency graph, atomic task ledger and execution index without implementing Procurement/Vendor capabilities.

## Mandatory entry gate

Stop with `PHASE_6_BLOCKED` unless one active checkpoint proves `RUNTIME_DISCOVERY_VERIFIED`, `RUNTIME_ARCHITECTURE_VERIFIED`, `PHASE_0_VERIFIED`, `PHASE_1_VERIFIED`, `PHASE_2_VERIFIED`, `PHASE_3_VERIFIED`, `PHASE_4_VERIFIED` and `PHASE_5_VERIFIED`. Reconcile repository/branch/HEAD/worktree ownership, schema/migrations, canonical vendor/rate, Operations/TMS/WMS and Finance/AP contracts, file/approval/job/API/access primitives, environment, baselines, unresolved errors/issues and handoff before planning.

## Required work

1. Read every persistent governance/context/status/task/change/decision/assumption/error/issues/handoff artifact and all Phase 6 sources.
2. Inspect actual repository modules, schemas, migrations, RLS/RBAC/field policy, APIs, jobs, files, tests, docs and commands. Never infer paths from this package.
3. Map all 17 capabilities and all 20 `PRC-*` anchors to workstream → epic → capability → feature slice → atomic implementation/verification/hardening/documentation/closure tasks.
4. Reconcile the single Phase 2 vendor/service/rate foundation, Phase 3 actual-cost/assignment lineage, Phase 4 vendor-bill/AP contracts and Phase 5 resource/capacity/assignment contracts; create an ADR/blocker for any duplicate ownership.
5. Split schema/migration, policy, service, REST/GraphQL, responsive UX, integration/job, test and documentation work into bounded tasks with exact dependencies and one owner.
6. Map `PRC-VND-US-001`, `FINTEST-016`, vendor lifecycle, rate validity/search, sourcing/RFQ/comparison, PO/contract, capacity/assignment, performance and invoice matching gates to implementation or verification tasks.
7. Define explicit ownership for external vendor identity/portal membership without adding a fifth access layer. BP-A08 keeps self-registration/portal tenant-configurable; unresolved Platform identity ownership blocks only affected tasks.
8. Keep HR employee/driver/payroll truth in Step 12, Customer Portal/Loyalty in Step 13 and AI recommendation/enterprise depth in Step 14.
9. Mark only dependency-clean tasks `READY`; all others remain `NOT_STARTED` or `BLOCKED` with exact prerequisites.

## Required execution-index columns

`task_id`, `parent_prompt`, `workstream`, `epic`, `capability`, `feature_slice`, `atomic_objective`, `source_ids`, `upstream`, `downstream`, `allowed_paths`, `forbidden_paths`, `migration_ids`, `api_contracts`, `access_controls`, `vendor_rate_po_match_invariants`, `tests`, `commands`, `evidence`, `rollback`, `owner`, `status`, `resume_point`.

## Phase 6 planning gates

- No vendor-master or rate task is `READY` until canonical Phase 2 ownership, duplicate/no-reentry rules and migration compatibility are proven.
- No activation/assignment task is `READY` until vendor status, assessment, compliance/document, service/coverage, contract/rate, capacity and override authority are explicit.
- No tax/bank task is `READY` without field classification, masking, maker-checker/MFA, current SME/provider evidence and Finance ownership boundaries.
- No rate/PO/contract task is `READY` without exact currency/UOM/tax/surcharge/tiering/rounding, validity, source/config snapshots and amendment/correction rules.
- No invoice-matching task is `READY` until the canonical Phase 4 vendor-bill/AP interface and Phase 3/5 actual-cost/ePOD/service evidence are reconciled; Procurement cannot post or pay.
- No external vendor portal task is `READY` until identity, invitation, record/field/file scope and revocation are proven without a fifth role layer.
- Native/offline sync, HRIS, full Customer Portal/Loyalty and autonomous AI/enterprise automation remain outside this phase.

## Completion gate

Mark kickoff `VERIFIED` only when the execution index has complete 17-capability/20-anchor coverage, no cycle/orphan/collision, exact repository paths and commands, resolved ownership boundaries, explicit runtime/evidence gates and a deterministic next eligible atomic task. Do not set `PHASE_6_VERIFIED`; only Prompt 271 may do that.
