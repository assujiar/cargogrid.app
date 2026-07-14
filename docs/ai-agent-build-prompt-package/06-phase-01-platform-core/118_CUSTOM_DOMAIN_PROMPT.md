# Prompt 118 — Custom Domain

**Prompt ID:** `CG-S6-PLT-015`  
**Package document:** `CG-AABPP-PLT-118`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-118.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-015` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Tenant Experience; Epic: Tenant Domain Routing; Capability: Custom domain lifecycle; Feature slice: Request→verify→activate→rotate→disable domain; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement secure tenant custom-domain registration, ownership verification, routing context and lifecycle without cross-tenant domain takeover.

## 5. Business value

Support enterprise white-label access with reliable tenant resolution and certificate/DNS operations.

## 6. Source requirement

PLT-WLB-001..004; custom-domain architecture/security; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Custom-domain schema/migrations/service/resolver/cache/tests/docs/runbook and approved provider adapter. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Live DNS/cert mutation without external authority, generic integration hub, auth bypass. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Tenant-domain records, normalized uniqueness, verification challenge/status, effective dates and audit with RLS.

## 14. API impact

Authorized register/verify/status/activate/disable contract and safe public resolution.

## 15. UI/UX impact

Admin view models/states for DNS guidance/verification/error; full portal UI later.

## 16. Security impact

Ownership verification, reserved/host normalization, takeover/rebinding prevention, HTTPS-only, redirect/cookie/origin allowlists.

## 17. Performance impact

Cache domain→tenant safely with invalidation; resolution on hot path bounded.

## 18. Audit impact

Record domain request/challenge/verify/activate/disable/cert events and actor.

## 19. Data migration impact

Map existing domains explicitly; never auto-claim by string match.

## 20. Detailed implementation tasks

1. Define normalized domain lifecycle, reserved rules, verification and tenant resolution.
2. Implement data model/service and provider-independent verification interface per approved architecture.
3. Integrate request host→tenant context, cache invalidation, HTTPS/origin/cookie security.
4. Add takeover/race/rebinding/cert failure tests, observability, runbook and docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized tenant verifies owned domain and HTTPS requests resolve correct tenant/brand.

## 22. Alternative flow

Domain pending/expired/disabled falls back or shows safe status per policy.

## 23. Exception flow

Duplicate/reserved/unverified/rebound domain, invalid host or certificate failure blocks activation.

## 24. Business rules

- One domain maps to one active tenant at a time; ownership must be proven.
- Custom domain changes presentation/routing, not access authorization.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Normalization/uniqueness/verification/activation atomic and cache-consistent.
- Host header/untrusted origin never selects unauthorized tenant.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Tenant Admin manages own domains; Supreme oversees reserved/global operations with audit.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/domains/subdomains, IDN/uppercase/trailing dot, duplicate/rebinding, expiry and invalid hosts. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Lifecycle/normalization/uniqueness/verification/cache/cert state tests.
- Domain takeover/host header/open redirect/cookie/origin/cross-tenant negatives.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Auth redirects/cookies, tenant context, white-label SSR, APIs and default domain.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-118.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Verified domains resolve only correct tenant over secure settings.
- Takeover/rebinding/cache/security/runbook evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

