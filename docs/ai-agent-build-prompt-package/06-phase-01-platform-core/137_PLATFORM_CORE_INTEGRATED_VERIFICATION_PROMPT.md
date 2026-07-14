# Prompt 137 — Platform Core Integrated Verification

**Prompt ID:** `CG-S6-PLT-034`  
**Package document:** `CG-AABPP-PLT-137`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-137.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-034` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Phase Verification; Epic: Platform Integration Gate; Capability: Cross-capability verification; Feature slice: Provisioned tenant through portals/engines/APIs/jobs/files; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Verify PLT-105..136 together at one checkpoint through realistic multi-tenant Platform Core flows.

## 5. Business value

Detect cross-capability access/data/contract/UX regressions before hardening and Commercial work.

## 6. Source requirement

PLT-105..136 logs; Phase 1 WBS/traceability; critical tenant test catalogue. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Verification tests/scripts/fixtures/logs/docs and no repair by default. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

New capability, broad refactor, gate suppression, shared/production systems. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Verify migrations/rebuild/upgrade/RLS/constraints/indexes/functions/seeds/types at one schema version.

## 14. API impact

Verify REST/GraphQL parity, API keys/webhooks and service contracts.

## 15. UI/UX impact

Verify Tenant/Supreme portal complete states, accessibility/responsive/browser and no dead actions.

## 16. Security impact

Run cross-tenant/four-layer/RBAC/RLS/field/record/support/file/key/webhook abuse matrix.

## 17. Performance impact

Run representative provisioning/access/query/job/file/portal budgets and live-OLTP guards.

## 18. Audit impact

Reconcile all privileged/config/engine/API/job/file events and Supreme risk disclosure.

## 19. Data migration impact

Verify clean and brownfield upgrade/data preservation; no production/shared mutation.

## 20. Detailed implementation tasks

1. Freeze checkpoint and collect all capability outputs/evidence.
2. Run end-to-end tenant provision→entitle→auth→hierarchy/user/role→access→configure/engine→API/job/file→admin flows.
3. Run isolation/abuse/concurrency/failure/recovery/migration/accessibility/performance matrices.
4. Produce integrated failure/gap report and exact repair tasks; do not hide/fix out of scope.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Two tenants use Platform Core end to end with correct isolation/access/audit.

## 22. Alternative flow

Suspended/unentitled/delegated/support/custom-domain/white-label/locale paths remain consistent.

## 23. Exception flow

Partial provisioning, revoked user, stale cache, worker/file/provider failure or invalid config recovers safely.

## 24. Business rules

- Isolated component pass does not imply integrated pass.
- Zero critical tenant/security/data/platform defect required for hardening entry.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- All outputs share checkpoint/schema/contract versions and traceability.
- No orphan/cycle/duplicate capability or unowned finding.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Test all four layers, service/API keys, support/impersonation and direct DB/API/portal paths.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two+ tenants, all principal layers, varied packages/orgs/config versions, files/jobs/API keys and failures. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Full CI/migration/RLS/RBAC/REST/GraphQL/job/file/portal E2E matrix.
- 18 tenant isolation scenarios, security/access/performance/accessibility/audit/recovery tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Phase 0 and every PLT-105..136 acceptance suite.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-137.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Integrated Platform Core passes one trusted checkpoint or exact blockers recorded.
- No Commercial/domain scope or external production mutation.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

