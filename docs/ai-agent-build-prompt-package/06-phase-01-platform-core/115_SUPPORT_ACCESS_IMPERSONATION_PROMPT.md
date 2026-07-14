# Prompt 115 — Support Access and Impersonation Control

**Prompt ID:** `CG-S6-PLT-012`  
**Package document:** `CG-AABPP-PLT-115`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-115.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-012` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Identity and Access; Epic: Privileged Support Operations; Capability: Time/purpose-bound support access; Feature slice: Grant→activate→impersonate→expire/revoke with banner/audit; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement controlled CargoGrid support access and impersonation with explicit tenant approval/policy, purpose, time bounds, re-authentication and full audit.

## 5. Business value

Enable support without invisible standing access or untraceable tenant actions.

## 6. Source requirement

PLT-IAM requirements; support/impersonation security rules; RPD access decisions. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Support grant/session schema/migrations/service/context/banner/tests/docs/runbook. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unapproved standing access, direct service-role browser use, domain admin features. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Model support grants/sessions/reason/expiry/scope/revocation and immutable-for-normal-role events with RLS.

## 14. API impact

Privileged create/approve/start/end/revoke/status contracts with re-auth/MFA-ready checks.

## 15. UI/UX impact

Reusable impersonation banner/context/reason/end action and denied/expired states; full portal integration later.

## 16. Security impact

No standing broad access; least scope, purpose/time bound, re-authentication, separation, tenant visibility and kill switch.

## 17. Performance impact

Grant/session checks request-cached with expiry/revocation invalidation.

## 18. Audit impact

Every grant, approval, start/end, context, action and revocation is recorded; RPD-022 limitation disclosed.

## 19. Data migration impact

No broad historical grant; existing support access must be inventoried/revoked/mapped explicitly.

## 20. Detailed implementation tasks

1. Define support grant/session lifecycle, authority, approval, scope and prohibited actions.
2. Implement privileged grant and session context integration with access evaluators.
3. Implement banner/reason/start/end/expiry/revoke and emergency kill switch primitives.
4. Add abuse/expiry/revocation/action-audit tests, docs and incident runbook.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized support user enters approved tenant context for limited purpose/time and actions are attributed.

## 22. Alternative flow

Emergency support uses recorded higher authority/shorter expiry and post-review.

## 23. Exception flow

Missing approval/reason, expired/revoked grant, prohibited action or context mismatch fails immediately.

## 24. Business rules

- Impersonation never changes underlying identity and must always be visibly indicated.
- Supreme authority/risk is disclosed; normal support cannot edit protected records without explicit policy.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Purpose/scope/start/end/expiry/revocation and action attribution mandatory.
- Session/cache invalidates promptly on revoke/expiry.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Support access layers over tenant entitlement/RBAC/RLS/field/record policy, not bypasses them.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Multiple tenants/support roles/grants, approvals, expiry/revocation, emergency and prohibited actions. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Grant/session/banner/re-auth/expiry/revoke/kill-switch tests.
- Cross-tenant, hidden impersonation, cache stale, privileged action audit and abuse negatives.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Auth, context, RBAC/RLS, audit and future portals.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-115.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Support access is visible, time/purpose/scope-bound and fully attributable.
- No standing/hidden/bypass access; expiry/revocation tests pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

