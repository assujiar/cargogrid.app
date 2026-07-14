# Prompt 123 — Approval Engine

**Prompt ID:** `CG-S6-PLT-020`  
**Package document:** `CG-AABPP-PLT-123`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-123.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-020` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Engines; Epic: Configurable Authorization Decisions; Capability: Approval routing and decision engine; Feature slice: Versioned rules, approver resolution, decision and escalation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement reusable approval definitions/requests/steps with deterministic approver resolution, separation of duties and audit.

## 5. Business value

Apply consistent configurable governance to commercial, operations, finance, vendor and HR processes.

## 6. Source requirement

PLT-CFG-001..004; 13 approval patterns/14 use cases; access rules; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Approval engine schema/migrations/service/contracts/tests/docs and isolated example. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Domain-specific approval policies beyond example, full inbox UI, finance overrides. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Approval definitions/versions/requests/steps/decisions/delegations/SLA/snapshots with tenant keys/RLS/constraints.

## 14. API impact

Define/simulate/publish/request/approve/reject/return/cancel/escalate/history contract.

## 15. UI/UX impact

Reusable pending approver/timeline/action view models; module inbox/page later.

## 16. Security impact

Approver RBAC/scope/field/record checks, separation of duties, delegation limits and no self-approval when prohibited.

## 17. Performance impact

Indexed pending inbox and compiled rules; no per-item N+1 approver resolution.

## 18. Audit impact

Definition/routing/assignment/delegation/decision/reason/override/escalation events.

## 19. Data migration impact

Module adoption maps existing approvals with explicit history strategy.

## 20. Detailed implementation tasks

1. Define approval patterns, rule inputs, steps, approver resolvers, decisions and snapshot semantics.
2. Implement definition lifecycle/simulation/publish and conflict/no-approver validation.
3. Implement idempotent request/routing/decision/delegation/escalation/cancel with concurrency.
4. Add access/audit/notification hook/tests/docs and representative approval example.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Valid request resolves authorized approvers and completes approved/rejected outcome once.

## 22. Alternative flow

Parallel/sequential/threshold/delegated/escalated route follows version snapshot.

## 23. Exception flow

No approver, separation conflict, expired delegation, stale record or concurrent decision fails safely.

## 24. Business rules

- Approval is explicit; UI button does not confer authority.
- Decision snapshot/reason/history preserved and normal roles cannot rewrite.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Routing deterministic for input/scope/date/version and no unresolved approver.
- Only pending authorized step can decide once.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Definition admin, requester, approver, observer and override permissions distinct and tenant-scoped.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Sequential/parallel/threshold, multi-level scopes, self-approval conflict, delegation, SLA/escalation, concurrency. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Definition/routing/simulation/snapshot/delegation/SLA tests.
- RBAC/RLS/separation/cross-tenant/concurrent decision/audit/notification/performance tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Workflow/config/RBAC/user/org and future module approval flows.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-123.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Approval routing/decisions are deterministic, access-safe and fully auditable.
- No self/duplicate/unauthorized decision or unresolved route.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

