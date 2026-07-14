# Prompt 170 — Shipment Lifecycle

**Prompt ID:** `CG-S8-OPS-004`  
**Package document:** `CG-AABPP-OPS-170`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-170.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-004` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Shipment Execution; Epic: Canonical Shipment State; Capability: Shipment lifecycle and status transitions; Feature slice: Draft→confirmed→planned→assigned→dispatched→in transit→delivered→ePOD→closed; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a canonical shipment lifecycle whose status projection is driven by validated transitions and operational events.

## 5. Business value

Give every user a consistent, auditable understanding of shipment progress and blockers.

## 6. Source requirement

OPS-SHP-001..004; OPS-TMS-001..004 basic slice; BPR lifecycle; Master Prompt Phase 3. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168..169; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-171..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Shipment Execution schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend versioned canonical transition/state history, current projection, reason/hold/cancel fields, optimistic version and transition idempotency constraints.

## 14. API impact

Provide one shared REST/GraphQL transition service with eligibility, command idempotency, current state/history and conflict responses.

## 15. UI/UX impact

Build accessible status timeline/action controls with permitted next states, reason capture, stale/conflict guidance and complete responsive states.

## 16. Security impact

Transition permission uses role, assignment, organization/customer/service scope and record state; client action visibility is not authority. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/shipment/current status/updated time; append/query histories efficiently and avoid replaying unbounded events per list row.

## 18. Audit impact

Record prior/new canonical state, display label, actor/source, reason, event/correlation/idempotency keys, config version and correction.

## 19. Data migration impact

Map legacy statuses to canonical states through reviewed mapping; unknown/invalid histories remain blocked for reconciliation.

## 20. Detailed implementation tasks

1. Define canonical lifecycle, transition matrix, terminal/reopen/cancel/hold rules and event linkage.
2. Implement atomic idempotent transition service and current-state projection.
3. Integrate assignment, milestone, exception, ePOD and billing gates without hard-coded tenant labels.
4. Build timeline/actions UX and API contracts.
5. Verify illegal transitions, concurrency, access, audit, migration and downstream state consistency.

## 21. Main flow

An authorized command moves a shipment through one valid canonical transition and appends complete history.

## 22. Alternative flow

Configured display labels/workflow vary while canonical semantics and downstream gates remain stable.

## 23. Exception flow

Illegal/stale/duplicate/unauthorized transition, missing prerequisite or terminal-state mutation fails without partial update.

## 24. Business rules

- Canonical state is stable; tenant labels do not alter lifecycle meaning.
- Milestone events may trigger transitions only through the same validated service.
- Normal users cannot rewrite history; corrections append evidence, subject to RPD-022 Supreme exception.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate transition source state/version, prerequisites, actor scope, reason and idempotency.
- Delivered/ePOD/closed states require configured evidence; canceled/held states require reason.
- Projection and history must reconcile after concurrent commands/retry.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Role/assignment/scope determines transition actions; customer/public surfaces see only allowed projected states and sanitized history. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

All states/transitions, invalid skips, hold/cancel/reopen, concurrent/retried commands, custom labels and cross-scope users. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Transition matrix/idempotency/concurrency/projection/history/database tests.
- RLS/RBAC/record/field/API parity/audit/cross-tenant tests.
- Timeline/action E2E, accessibility, high-history performance and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Job/shipment status, workflow/status engines, milestones, tracking, ePOD and billing readiness. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-170.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Only allowed transitions change shipment state.
- History and projection remain consistent under retry/concurrency.
- All downstream consumers use canonical state rather than tenant label.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-005` / `OPS-171` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

