# Prompt 113 — RLS Tenant Policy Foundation

**Prompt ID:** `CG-S6-PLT-010`  
**Package document:** `CG-AABPP-PLT-113`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-113.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-010` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Identity and Access; Epic: Database Tenant Isolation; Capability: RLS policy primitives; Feature slice: Deny-by-default tenant policy families and tests; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement reusable Supabase/PostgreSQL RLS primitives and initial policies for Platform Core tenant tables.

## 5. Business value

Make tenant isolation a database guarantee rather than an application convention.

## 6. Source requirement

NFR-SEC-001; PLT-IAM/TNT requirements; RLS architecture; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Approved RLS helper/policy migrations/grants/tests/docs and tenant-key indexes. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Disabling RLS, broad grants/service bypass, unrelated domain tables, applied migration edits. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Enable/retain RLS, tenant-aware keys/FKs/indexes, explicit operation policies and least-privilege grants.

## 14. API impact

Verify REST/GraphQL/server requests cannot bypass policies and map denials safely.

## 15. UI/UX impact

No UI authorization; denied states consume server errors only.

## 16. Security impact

Primary scope: auth context, tenant/member/scope helpers, service identities, migration/support exceptions and cross-tenant denial.

## 17. Performance impact

Measure representative policy plans; tenant-leading indexes and stable non-recursive helpers.

## 18. Audit impact

Record policy changes and privileged bypass/use; disclose Supreme Admin exception.

## 19. Data migration impact

New migrations only; backfill missing tenant keys before enforcement with separate checkpoints.

## 20. Detailed implementation tasks

1. Inventory Platform Core tenant tables/operations/principals and policy matrix.
2. Implement stable helper functions/grants and explicit SELECT/INSERT/UPDATE/DELETE policies.
3. Integrate tenant-aware constraints/indexes and safe service/job/migration paths.
4. Add database/API/job/report/file cross-tenant tests and performance evidence.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized tenant context reads/writes only permitted own rows.

## 22. Alternative flow

Scoped/support/service operation uses explicit least-privilege path.

## 23. Exception flow

Missing/forged/wrong-tenant context or unauthorized operation fails at database boundary.

## 24. Business rules

- Every tenant-scoped table has RLS; application filters are insufficient.
- No broad service-role bypass and no policy disablement for tests/jobs.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- USING/WITH CHECK cover every operation; grants and helpers do not create public reachability.
- Cross-tenant references are impossible by constraint/policy.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Matrix four layers, worker/service, support and Supreme privileged behavior explicitly.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two+ tenants, roles/scopes, missing/forged claims, support expiry and service jobs. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Direct DB operation policy tests and tenant-aware FK/constraint tests.
- REST/GraphQL/job/file/report cross-tenant/IDOR and policy performance tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Tenant lifecycle, memberships, RBAC and existing migration rebuild/upgrade.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-113.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Platform Core tenant tables fail closed across all operations/interfaces.
- No bypass/recursion/performance regression; policy/docs evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

