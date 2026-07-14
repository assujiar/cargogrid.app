# Prompt 108 — Four-Layer Identity and Access Context

**Prompt ID:** `CG-S6-PLT-005`  
**Package document:** `CG-AABPP-PLT-108`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-108.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-005` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Identity and Access; Epic: Access Context; Capability: Four-layer principal model; Feature slice: Canonical principal/tenant/org/customer context resolution; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical server-side access context for Supreme Admin, Tenant Admin, tenant organizational users and customer users.

## 5. Business value

Give every database/API/job/file/UI decision one consistent principal/tenant/scope foundation.

## 6. Source requirement

CPD four layers; PLT-IAM-001..004; Customer Portal access rules; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Principal/membership schema/migrations/context resolver/guards/tests/docs. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Full RBAC/RLS/portals, hard-coded customer roles and tenant-specific branches. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Model memberships/principal types/context references and constraints without embedding permissions in layer labels.

## 14. API impact

Resolve verified context for REST/GraphQL/server actions/jobs; reject ambiguous/multi-tenant context.

## 15. UI/UX impact

Expose safe context/portal selector and role labels later; no client authority.

## 16. Security impact

Deny by default, prevent layer escalation/context forgery, distinguish support/impersonation and service identities.

## 17. Performance impact

Resolve bounded context with indexed membership and request caching; no N+1.

## 18. Audit impact

Record principal/tenant/org/customer context and privileged switches without sensitive claims.

## 19. Data migration impact

Map existing memberships/principal types deterministically; no broad default layer.

## 20. Detailed implementation tasks

1. Define principal/layer taxonomy, memberships and allowed context dimensions.
2. Implement server context resolver and typed contract from authenticated identity plus explicit selection.
3. Integrate base guards/context propagation to DB/API/jobs/files/audit.
4. Add cross-layer/tenant ambiguity/escalation tests and docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Identity resolves exactly one authorized principal context for requested tenant/portal.

## 22. Alternative flow

Multi-membership user switches to another authorized context with re-evaluation/audit.

## 23. Exception flow

Missing/ambiguous/forged/inactive membership or incompatible portal fails closed.

## 24. Business rules

- Layer is not permission; RBAC/scope/field/record still required.
- Customer user context is constrained to linked company/account/site relationships.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Context includes verified identity, principal type, tenant, org/customer references and session metadata.
- All required dimensions come from authoritative server data.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Supreme global, Tenant Admin tenant, organizational user scope and customer-company scope remain distinct.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Identities in each layer, multi-membership, inactive/suspended tenant, forged context and customer-company links. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Context resolution/switch/ambiguity/inactive/expiry tests.
- Cross-layer/tenant escalation, API/job/file propagation and audit tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Auth sessions, tenant entitlement, future RBAC/RLS and portal routing.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-108.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Every request obtains one unforgeable canonical access context or fails closed.
- No permission assumption from layer and no tenant leakage.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

