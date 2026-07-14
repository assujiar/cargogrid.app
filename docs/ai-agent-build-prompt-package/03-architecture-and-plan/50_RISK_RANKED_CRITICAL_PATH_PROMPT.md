# Prompt 50 — Risk-Ranked Critical Path

**Prompt ID:** `CG-S3-ARCH-015`  
**Package document:** `CG-AABPP-ARCH-050`  
**Version:** `0.4.0`  
**Runtime output:** `docs/architecture/15_RISK_RANKED_CRITICAL_PATH.md`

## Objective and value

Identify the dependency-constrained and risk-adjusted path that governs safe CargoGrid delivery, so effort is sequenced by blocker reduction rather than feature visibility.

## Preconditions

Prompts 36–49 are complete. Use WBS dependencies, release train, traceability, Step 2 debt/risk register, architecture ADRs, and direct-GA gates. Do not fabricate durations or staffing.

## Required tasks

1. Build the dependency graph from atomic WBS tasks, gates, ADRs, migrations, contracts, environments, tests, and external verification.
2. Identify logical critical path and near-critical branches using dependency depth when validated duration estimates are unavailable.
3. Rank tasks using severity, likelihood, blast radius, tenant/security/finance/data exposure, dependency centrality, reversibility, detection strength, uncertainty, and remediation complexity.
4. Highlight foundation blockers: repository strategy, target boundaries, schema/migrations, tenant/RLS/RBAC, configuration engines, API/contracts/jobs/files, CI/environments, test data, observability, backup/recovery, and compliance evidence.
5. Overlay RPD-022, direct GA/no pilot, zero critical defects, contract-silent recovery, custom integrations, and time-sensitive Indonesia tax/payroll verification.
6. Identify concurrency lanes that are genuinely independent, integration checkpoints, resource/skill assumptions, freeze points, and stop/rollback triggers.
7. Define risk-burn-down evidence and recalculation triggers when ADRs, runtime facts, estimates, failures, or requirements change.
8. Produce the ordered critical path, top risks, gate owners, and exact next eligible architecture-to-prompt handoff.

## Required output

Include method/scales, dependency graph summary, critical and near-critical paths, risk-ranked task table, concurrency lanes, accepted-risk overlay, external gates, risk burn-down plan, stop/rollback triggers, assumptions, sensitivity, and recalculation rules.

## Completion gate

Complete only when every critical-path item exists in the WBS/traceability matrix, ranking is reproducible, uncertainty is explicit, no unverified dates are claimed, and all critical accepted risks affect sequencing/gates.
