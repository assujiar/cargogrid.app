# Prompt 431 — Tenant Merge and Split (admin-run migration)

**Prompt ID:** `CG-S6-PLT-039`  
**Package document:** `CG-AABPP-PLT-431`  
**Version:** `0.19.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-431.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint. Prompt 105 (Tenant Provisioning and Lifecycle) must be `VERIFIED` — this capability operates on the lifecycle that prompt establishes and cannot precede it.

> **Numbering note.** This prompt is numbered `431` because it was authored at package revision `0.19.0` (`ADR-0028`), after the package's contiguous `00..430` sequence was already fixed. Its number records when it was written; its **directory and its §9/§36 fields record where it executes** — Phase 1 Platform Core, immediately after Prompt 105. Renumbering the 325 files between `106` and `430` to seat it at its execution position would have falsified every committed citation to them, which is the same append-only reasoning that governs every other correction in this revision. See `FPV-F001` in `docs/build-log/final-package-validation/FINAL_GAP_RISK_REGISTER.md`.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-039` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.19.0`.

## 3. Workstream

Workstream: Multi-Tenancy; Epic: Tenant Control Plane; Capability: Tenant merge and split; Feature slice: preflight→approval→backup→execute→reconcile→audit; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant merge and tenant split as an admin-run, preflight-gated, approved, backed-up, reconciled and fully audited migration — never a tenant self-service action, and never a silent bulk update.

## 5. Business value

Real customers reorganise: two acquired companies consolidate onto one tenant, or one tenant separates into independent legal entities. Without a governed path this is done by hand against production data, which is where cross-tenant contamination and unrecoverable data loss actually originate.

## 6. Source requirement

`RPD-020` (tenant merge/split is an admin-run migration requiring preflight, approval, backup, reconciliation and audit evidence; no tenant self-service merge/split); PLT-TNT-001..004; the canonical tenant lifecycle established by Prompt 105; `RPD-022` (termination/disclosure) and `RPD-025` (retention and legal hold) where a merge retires a tenant identity. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint. Enumerate every table carrying `tenant_id` before planning — the blast radius of this capability is the whole schema, and a table discovered late is a table migrated wrongly.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict. Confirm a working, rehearsed restore path exists before any execution capability is built — a migration tool without a proven restore is a data-loss tool.

## 9. Upstream dependencies

`CG-S6-PLT-002` (Prompt 105, tenant lifecycle) must be `VERIFIED`. `{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; every tenant-scoped domain (Commercial, Operations, Finance, Procurement, HRIS, Portal, Loyalty, Intelligence), every `tenant_id`-bearing table, RLS policies, audit trail, entitlement and subscription state, uploaded files and their storage paths, and every foreign key that crosses a tenant boundary once two tenants become one.

## 11. Allowed files/folders

Exact tenant control-plane schema/migrations/service/tests/docs paths from WBS. Resolve exact paths. This capability will exceed the normal 5–15 file, 1–3 migration boundary and **must be split** into at least: preflight and reporting; approval and authority; execution engine; reconciliation and evidence.

## 12. Forbidden files/folders

Domain modules, unrelated auth/UI, destructive data cleanup, applied migrations and tenant forks. Preserve unrelated/user-owned changes, applied migrations and protected decisions. **Never** implement merge/split as raw SQL run outside the application's own audited path.

## 13. Database impact

Add merge/split plan, approval, execution and reconciliation entities carrying source and target tenant identity, per-table row counts before and after, an immutable plan snapshot, and a durable link from every migrated record to the plan that moved it. Record provenance on the migrated rows; a record that changed tenant with no trace of why is indistinguishable from a leak.

## 14. API impact

Provide authorized preflight/plan/approve/execute/status/reconcile contracts through the shared service for REST/GraphQL. Execution must be idempotent per plan and resumable after interruption — a half-migrated tenant is the worst reachable state and must be recoverable rather than merely detected.

## 15. UI/UX impact

Supreme Admin surfaces only: plan builder, preflight report, explicit approval step showing exactly what will move, live execution progress, and a reconciliation report. No tenant-facing surface whatsoever. The approval screen must show counts and conflicts before the irreversible step, not after.

## 16. Security impact

Supreme Admin authority only, with step-up authorization on execution. This capability legitimately moves data across a tenant boundary, which makes it the single most sensitive operation in the platform — every other control assumes that boundary holds. Execution must be impossible without an approved plan, and the plan must be immutable once approved.

## 17. Performance impact

Batch and checkpoint execution; bound transaction size so a large tenant does not hold locks that stall live traffic. Report progress per table. Prefer a longer, resumable, observable migration over a single transaction that either succeeds or leaves nothing to inspect.

## 18. Audit impact

Record the requester, the approver (never the same identity), the plan snapshot, per-table before/after counts, every conflict resolution decision and its rationale, start and end times, and the reconciliation outcome. This evidence is what `RPD-020` exists to require; it is the deliverable, not a side effect.

## 19. Data migration impact

Additive migrations only. Identify and resolve every unique constraint that two tenants can independently satisfy but a merged tenant cannot (customer codes, vendor codes, invoice numbers, employee numbers, item codes) — preflight must surface each collision with a decided resolution before approval, never resolve one silently at execution time.

## 20. Detailed implementation tasks

1. Enumerate every `tenant_id`-bearing table and classify each as move, merge-with-collision-risk, or recompute.
2. Implement preflight: row counts, collision detection across every unique constraint, orphan and cross-reference detection, and a machine-readable report.
3. Implement plan approval with immutability, separation of requester and approver, and step-up authorization.
4. Implement resumable, checkpointed execution with per-record provenance.
5. Implement reconciliation: prove every source row landed exactly once, and that no row landed in the wrong tenant.
6. Implement split as the inverse: partition by an explicit selector, never by inference.
7. Add observability, tests, docs and rollback evidence. Compare baseline and post-change evidence.

## 21. Main flow

Supreme Admin builds a plan, runs preflight, resolves every reported collision explicitly, obtains a separate approver's approval, takes a backup, executes, and reads a reconciliation report proving the outcome.

## 22. Alternative flow

Execution interrupted mid-run resumes from its last checkpoint without duplicating work. A preflight reporting unresolved collisions blocks approval rather than proceeding with a default resolution.

## 23. Exception flow

Unapproved execution, plan mutated after approval, self-approval, collision unresolved at execution time, reconciliation mismatch, missing backup evidence, or any row landing in a tenant the plan did not name — each fails safely, leaves the audit trail intact, and reports precisely which record and which rule.

## 24. Business rules

- Merge and split are admin-run migrations. No tenant self-service, at any subscription tier.
- Execution without a preflight, an approval by a second identity, and recorded backup evidence is forbidden.
- An approved plan is immutable; changing it requires a new plan and a new approval.
- A reconciliation mismatch is a failure, never a warning.
- Retired tenant identities follow `RPD-022` disclosure and `RPD-025` retention/legal hold — a merged-away tenant is not deleted.
- Tenant isolation holds for every other operation in the platform; this one is the sole, governed exception and must prove itself each time.

## 25. Validation rules

- Source and target tenants exist, are distinct, and are in a state the lifecycle permits migrating.
- Every unique constraint collision is detected at preflight and carries an explicit resolution before approval.
- Post-execution row counts reconcile exactly, per table, with no unexplained difference in either direction.
- Validate at server and database boundaries; no unresolved placeholder and no client-only rule.

## 26. Access rules

- Supreme Admin only, with step-up authorization at execution.
- Requester and approver must be different identities.
- Tenant Admins may see that a migration affecting their tenant occurred, and its outcome, but may neither request nor approve one.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets throughout.

## 27. Test data requirement

At least three tenants with overlapping natural keys (the same customer code, vendor code and invoice number in two tenants), records in every domain, uploaded files, active users with memberships in more than one tenant, a tenant under legal hold, and a deliberately interrupted execution. Use synthetic or redacted data only.

## 28. Tests to create/update

- Preflight collision detection across every unique constraint, proven with a real collision per constraint.
- Approval authority, immutability, and self-approval denial.
- Idempotent and resumable execution, including a mid-run interruption.
- Reconciliation proving exactly-once landing and correct tenant for every row.
- Negative: unapproved execution, mutated plan, execution against a legal-hold tenant, and any row reaching a tenant the plan did not name.
- Cross-tenant isolation for every *other* tenant during and after a migration — the neighbouring tenant must be provably unaffected.

## 29. Regression tests

- Full tenant lifecycle, RLS/RBAC, entitlement, audit and every domain's own suite against both source and target tenants after a merge.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands and results; no unsafe auto-install and no shared database.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-431.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs, a dedicated operator runbook under `docs/runbooks/`, and phase handoff.

## 32. Rollback/recovery note

Preserve the last trusted checkpoint. A backup taken and verified immediately before execution is mandatory and its evidence recorded on the plan. Define the exact restore path; a partially executed plan resumes or restores, never "continues manually". Stop on partial or untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Preflight detects every seeded collision; approval blocks while any is unresolved.
- Execution is idempotent and resumable; a mid-run interruption resumes without duplication.
- Reconciliation proves exactly-once landing per table, with no unexplained difference.
- Every other tenant is provably unaffected.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree, **and** at least one full merge and one full split have been executed end to end against seeded multi-tenant data with reconciliation passing. Phase completion or readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; per-table before/after counts for the rehearsed merge and split; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance and dependencies pass; otherwise output the exact blocked/failed/partial resume prompt. This prompt executes within Phase 1 after Prompt 105 despite its `431` number — see the numbering note at the head of this file.
