# Prompt 107 — Supabase Auth Integration

**Prompt ID:** `CG-S6-PLT-004`  
**Package document:** `CG-AABPP-PLT-107`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-107.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-004` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Identity and Access; Epic: Authentication Foundation; Capability: Supabase Auth integration; Feature slice: Identity/session/MFA-ready server integration; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement Supabase Auth integration with server-safe sessions, identity linkage, invitation/recovery and MFA-ready controls.

## 5. Business value

Provide secure authentication for all four layers without mixing identity with authorization.

## 6. Source requirement

PLT-IAM-001..004; Supabase fixed stack; auth/session requirements; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Approved auth client/server/middleware/schema-link/tests/docs and minimal shared auth UI paths. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Role/permission logic outside integration, real identities/secrets, broad portal redesign. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Link auth identities to platform user/membership records using stable IDs and safe triggers/functions only if approved.

## 14. API impact

Implement server auth context/session refresh/logout/recovery/invite contracts and safe errors.

## 15. UI/UX impact

Implement only minimal reusable auth states/components if within slice; full portal auth screens may be child tasks.

## 16. Security impact

Secure cookies/tokens, CSRF, redirect allowlist, enumeration resistance, rate limits, session revocation, MFA-ready and server-only service role.

## 17. Performance impact

Avoid repeated auth round trips; cache only safe session context and handle refresh races.

## 18. Audit impact

Log security-relevant login/invite/recovery/revocation/MFA/privileged events without tokens.

## 19. Data migration impact

Additive identity-link migrations; reconcile existing identities without creating duplicates.

## 20. Detailed implementation tasks

1. Inspect verified Supabase/auth patterns and define identity versus membership/role boundaries.
2. Implement server/client auth clients, session middleware/context and stable identity linkage.
3. Implement invitation/activation/recovery/logout/revocation paths with safe redirect/error behavior.
4. Add MFA-ready extension, abuse/race tests, observability, docs and recovery.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Valid invited/registered identity authenticates and receives server-verified session context.

## 22. Alternative flow

Recovery/refresh/re-auth or optional MFA path succeeds within policy.

## 23. Exception flow

Expired/revoked/forged token, duplicate identity, invalid redirect or rate abuse fails safely.

## 24. Business rules

- Authentication proves identity only; entitlement/RBAC/RLS determine access.
- Service-role key never enters browser/client bundle.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Session lifecycle, cookie attributes, redirect allowlist and identity linkage deterministic.
- No account enumeration or orphan/duplicate membership.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Anonymous/authenticated/service/support principals have explicit boundaries; no implicit tenant membership.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Synthetic identities across layers/tenants, expired/revoked tokens, concurrent refresh, invalid redirects and duplicate emails. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Auth/session/invite/recovery/revocation/refresh/MFA-ready tests.
- CSRF/open redirect/enumeration/rate/client-secret negatives and tenant membership integration.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Existing auth, SSR/middleware, CI/env validation, tenant provisioning and future portals.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-107.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Auth flows work securely with stable identity linkage and no authorization conflation.
- Negative/session/secret/audit/docs evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

