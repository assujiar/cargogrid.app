# Prompt 136 — Supreme Admin Portal

**Prompt ID:** `CG-S6-PLT-033`  
**Package document:** `CG-AABPP-PLT-136`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-136.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-033` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Portals; Epic: CargoGrid Control Plane; Capability: Supreme Admin portal; Feature slice: Global tenant/control/config/support/audit administration shell; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement Supreme Admin portal shell and bounded control-plane workflows reflecting literal absolute CRUD while disclosing integrity limitations.

## 5. Business value

Let CargoGrid operate tenants, packages, platform defaults, support and global controls with explicit risk/audit.

## 6. Source requirement

Supreme Admin CPD/RPD-022; Platform Admin requirements; PLT-105..135; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Supreme portal shell/routes/components/privileged adapters/tests/docs and bounded workflows. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Direct client service-role/database, unreviewed destructive bulk action, domain feature admin. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

No direct client DB; privileged server services still use explicit authorization/audit and safe transactions.

## 14. API impact

Privileged REST/GraphQL operations with re-auth/MFA-ready, purpose/reason, idempotency and safe errors.

## 15. UI/UX impact

Primary scope: Supreme shell/global tenant/package/config/support/audit/health workflows split into bounded child slices and complete states.

## 16. Security impact

Re-authentication, high-risk confirmation, separation where possible, no browser service key and explicit destructive impact preview.

## 17. Performance impact

Paginated global queries/tenant filters, asynchronous bulk operations and strict query guards.

## 18. Audit impact

Every privileged view/change/delete/override/support action recorded, while disclosing Supreme can also alter audit itself.

## 19. Data migration impact

No uncontrolled data change; destructive/bulk actions require backup/dependency/rehearsal/explicit approval.

## 20. Detailed implementation tasks

1. Map Supreme IA/routes/high-risk operation matrix and risk disclosures.
2. Implement privileged shell/context/re-auth/banner/confirmation/impact preview/complete states.
3. Implement bounded tenant/package/platform/support/audit workflows over approved services.
4. Add absolute CRUD/high-risk/tenant-switch/accessibility/security/E2E/performance/docs tests.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authenticated/re-authorized Supreme Admin performs allowed global operation with reason/impact/audit.

## 22. Alternative flow

Support/impersonation or bulk operation uses time/purpose-bound/async guarded path.

## 23. Exception flow

Stale confirmation, dependency/retention/legal-hold, partial bulk failure or lost trust stops/reconciles.

## 24. Business rules

- Supreme Admin has literal absolute CRUD; package must not pretend immutable/tamper-proof evidence.
- High authority does not justify service keys in browser or hidden destructive effects.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Tenant context/global scope/re-auth/reason/impact/idempotency deterministic.
- Bulk/partial operations produce reconciled per-item results.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Only Supreme principals; support roles use separate grants. Every privileged action is attributed.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/states/packages, high-risk edits/deletes, legal hold, stale re-auth, bulk partial failure and support grants. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Route/context/re-auth/confirmation/impact/bulk/recovery/accessibility tests.
- Cross-role/tenant confusion/service-secret/security/audit/RPD-022 disclosure/E2E/load tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Tenant lifecycle/entitlements/config/access/audit/support and Tenant Admin portal.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-136.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Supreme operations are explicit, guarded, attributable and operationally usable.
- Absolute CRUD semantics/risk disclosure accurate; no hidden key/bulk corruption.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

