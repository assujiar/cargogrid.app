# Prompt 105 — Tenant Provisioning and Lifecycle

**Prompt ID:** `CG-S6-PLT-002`  
**Package document:** `CG-AABPP-PLT-105`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-105.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-002` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Multi-Tenancy; Epic: Tenant Control Plane; Capability: Tenant provisioning/lifecycle; Feature slice: Create→activate→suspend→reactivate→terminate tenant; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement one canonical tenant lifecycle with idempotent provisioning, isolated bootstrap, guarded state transitions and auditable recovery.

## 5. Business value

Create reliable SaaS tenant onboarding and control without manual data duplication or cross-tenant risk.

## 6. Source requirement

PLT-TNT-001..004; CPD/RPD tenant decisions; canonical lifecycle; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Exact tenant control-plane schema/migrations/service/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Domain modules, unrelated auth/UI, destructive data cleanup, applied migrations and tenant forks. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Add tenant/control-plane entities, stable tenant IDs, unique constraints, state/version/effective dates, bootstrap transaction and tenant-aware dependencies.

## 14. API impact

Provide authorized idempotent provision/status/transition contract through shared service for REST/GraphQL.

## 15. UI/UX impact

Foundation states for later admin portals; no broad portal screen unless task is split/authorized.

## 16. Security impact

Only authorized Supreme control plane provisions/terminates; strict tenant context and no service-role client exposure.

## 17. Performance impact

Bound bootstrap steps and indexes; provisioning may be asynchronous with progress/retry where required.

## 18. Audit impact

Record requester, reason, plan/config snapshot, transitions, bootstrap effects and failures.

## 19. Data migration impact

Additive migrations and deterministic reference/seed data; preserve existing brownfield tenants.

## 20. Detailed implementation tasks

1. Define canonical tenant identity, lifecycle/state machine, transition authority and invariants.
2. Implement idempotent transactional provisioning/bootstrap and compensating recovery.
3. Implement suspend/reactivate/terminate semantics without unsafe deletion; retain legal/audit obligations.
4. Add observability, retries, tests, docs and downstream entitlement/access hooks.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized request provisions one isolated active tenant with deterministic bootstrap.

## 22. Alternative flow

Retry with same idempotency key returns/reconciles prior result; suspension/reactivation preserves data.

## 23. Exception flow

Duplicate domain/key, partial bootstrap, invalid transition, dependency failure or termination with blockers fails safely.

## 24. Business rules

- Tenant lifecycle is canonical and cannot be hard-coded per customer.
- Termination follows retention/legal hold and RPD-022 disclosure.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Unique identity, allowed transitions, bootstrap completeness and idempotency are server/DB enforced.
- No active tenant can share another tenant’s scoped records.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Supreme Admin control authority only; later Tenant Admin sees own tenant status but cannot provision global tenants.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two+ tenants, duplicate request, partial failure, suspended/terminated/legal-hold states and concurrent provisioning. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- State/constraint/idempotency/retry/recovery/migration tests.
- RLS/cross-tenant/bootstrap/audit/API contract/performance tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Existing tenant data, auth, seeds, configuration and discovery baseline.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-105.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Lifecycle works idempotently with full isolation and recoverable partial failure.
- No tenant/data loss or unsupported deletion; gates/docs pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

