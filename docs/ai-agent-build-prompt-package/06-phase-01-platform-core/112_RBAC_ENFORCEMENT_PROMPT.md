# Prompt 112 — RBAC Enforcement

**Prompt ID:** `CG-S6-PLT-009`  
**Package document:** `CG-AABPP-PLT-112`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-112.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-009` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Identity and Access; Epic: Authorization Runtime; Capability: RBAC plus scope enforcement; Feature slice: Shared authorization evaluator and guards; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement server-authoritative RBAC evaluation combining published roles, canonical permissions, organizational scope and principal context.

## 5. Business value

Enforce consistent least-privilege action authorization across APIs, jobs, files and UI entry points.

## 6. Source requirement

PLT-IAM-001..004; NFR-SEC-002; role/permission catalogue; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

RBAC evaluator/guards/cache/schema integration/tests/docs and representative adapters. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Broad domain integration, RLS weakening, role-name authorization, full portals. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Implement indexed assignment/scope evaluation data and safe functions only where approved; no RLS replacement.

## 14. API impact

Shared guard for REST/GraphQL/server actions with safe deny semantics.

## 15. UI/UX impact

Expose evaluated capabilities for presentation only; server remains authoritative.

## 16. Security impact

Deny default, least privilege, separation of duties, cache invalidation, no self-escalation or role-name logic.

## 17. Performance impact

Bound evaluator queries and cache by tenant/principal/role version with prompt invalidation.

## 18. Audit impact

Privileged decisions/assignment changes/denials as policy requires, without leaking resource existence.

## 19. Data migration impact

Migrate assignments/version references deterministically; no permissive fallback.

## 20. Detailed implementation tasks

1. Define evaluator inputs, permission/scope precedence and deny behavior.
2. Implement shared authorization service/guards and cache invalidation.
3. Integrate representative server/API/job/file paths without duplicating business rules.
4. Add role/scope/denial/expiry/concurrency tests, observability and docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized principal with entitled permission and valid scope performs action.

## 22. Alternative flow

Multiple roles/scopes combine according to documented deterministic policy.

## 23. Exception flow

Missing/revoked/stale/conflicting/out-of-scope permission fails closed.

## 24. Business rules

- Role names/titles never authorize; canonical permissions and scope do.
- RBAC does not replace RLS or field/record checks.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Evaluation deterministic for role versions/effective dates/context.
- Revocation/role change invalidates cache within policy.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Cover all four layers, service identities and delegated administrators.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/roles/scopes/versions, revoked assignment, conflicts, support/customer principals. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Evaluator/precedence/cache/revocation/guard tests.
- API/GraphQL/job/file/UI capability and cross-tenant/escalation negatives.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Role builder, user lifecycle, context resolver and future RLS/portals.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-112.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- RBAC decisions are consistent, fast and deny-by-default at all integrated boundaries.
- No escalation/client-only enforcement; audit/tests pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

