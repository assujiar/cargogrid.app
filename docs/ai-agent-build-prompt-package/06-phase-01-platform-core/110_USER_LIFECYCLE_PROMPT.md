# Prompt 110 — User Lifecycle

**Prompt ID:** `CG-S6-PLT-007`  
**Package document:** `CG-AABPP-PLT-110`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-110.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-007` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Identity and Access; Epic: User Administration; Capability: User invitation/membership lifecycle; Feature slice: Invite→activate→suspend→reactivate→revoke/offboard; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant-aware user and membership lifecycle linked to Supabase identities, organizations, entitlements and auditable access revocation.

## 5. Business value

Onboard/offboard users safely without orphan access or cross-tenant identity duplication.

## 6. Source requirement

PLT-IAM-001..004; auth/user lifecycle; support/security requirements; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

User/membership/invitation schema/migrations/service/contracts/tests/docs and bounded notification hook. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Full role builder/portal, HR employee lifecycle, real user data and broad email provider integration. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Model user profile, tenant/customer memberships, invitations, lifecycle, org assignments and uniqueness constraints.

## 14. API impact

Authorized invite/resend/cancel/activate/update/suspend/reactivate/revoke contract.

## 15. UI/UX impact

Typed lifecycle/status/error states for admin portals; full UI in PLT-135/136.

## 16. Security impact

No enumeration, least privilege, invitation expiry, session/token revocation and sensitive profile masking.

## 17. Performance impact

Indexed membership/user lookup and paginated admin listing.

## 18. Audit impact

All invitation/profile/status/membership/org changes and revocation events.

## 19. Data migration impact

Reconcile existing identities/memberships idempotently; no duplicate email-based trust across tenants.

## 20. Detailed implementation tasks

1. Define user versus auth identity versus tenant/customer membership lifecycle.
2. Implement invitation/membership/profile/org assignment and transition service.
3. Integrate auth activation/session revocation and downstream role/access cleanup.
4. Add bulk-safe boundaries, tests, audit, notifications, docs and recovery.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized admin invites user; identity activates into correct tenant/org membership.

## 22. Alternative flow

Existing identity receives additional authorized membership without account duplication.

## 23. Exception flow

Expired/duplicate/unauthorized invite, suspended tenant, last-critical-admin or revocation failure stops safely.

## 24. Business rules

- Identity may have multiple memberships; each access context is explicit.
- Offboarding revokes access while preserving attributed records/audit.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Invitation/status/membership transitions and uniqueness deterministic.
- Revocation propagates to sessions/context/cache within policy.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Supreme manages global support/platform identities; Tenant Admin only own tenant within delegated authority.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

New/existing identities, multiple tenants/orgs, expired invite, suspension/reactivation, last admin and concurrent invites. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Lifecycle/invite/membership/session revocation/uniqueness/concurrency tests.
- Enumeration/cross-tenant/RBAC/RLS/audit/notification tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Supabase Auth, context resolution, tenant entitlement and organization hierarchy.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-110.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- User/membership lifecycle is secure, idempotent and fully auditable.
- Revoked users lose access without losing business attribution.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

