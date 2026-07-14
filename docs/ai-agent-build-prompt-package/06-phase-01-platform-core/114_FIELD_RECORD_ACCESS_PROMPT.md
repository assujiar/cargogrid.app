# Prompt 114 — Field-Level and Record-Level Access

**Prompt ID:** `CG-S6-PLT-011`  
**Package document:** `CG-AABPP-PLT-114`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-114.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-011` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Identity and Access; Epic: Fine-Grained Authorization; Capability: Field and record policy enforcement; Feature slice: Shared policy model and projection/filter guards; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement versioned field-level and record-level access controls layered over RBAC/RLS for Platform Core.

## 5. Business value

Prevent sensitive attribute and record leakage through API, UI, search, export, reports and files.

## 6. Source requirement

NFR-SEC-002; UX/Data access design; permission/scope rules; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Fine-grained policy schema/migrations/evaluator/projections/tests/docs and bounded adapters. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Domain-specific policies beyond foundation examples, client-only authorization, broad RLS changes. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Model policy/conditions/ownership/sharing safely; use RLS/views/functions only where approved.

## 14. API impact

Authorize records and project/mask fields identically for REST/GraphQL; prevent filter/sort inference.

## 15. UI/UX impact

Render hidden/masked/read-only/denied states from server metadata, not local guesses.

## 16. Security impact

Primary scope: field read/write/export/search/report and record owner/shared/org scope with deny default.

## 17. Performance impact

Batch/project policies without per-field/per-row N+1; cache versioned policies safely.

## 18. Audit impact

Audit sensitive field reads/changes/exports and record sharing/override as required.

## 19. Data migration impact

Seed canonical field/resource IDs and migrate policies without broad default access.

## 20. Detailed implementation tasks

1. Define resource/field IDs, sensitivity, operations and record policy condition model.
2. Implement server policy evaluator/projection/input whitelist and record-scope guard.
3. Integrate representative REST/GraphQL/search/export/file paths and safe UI metadata.
4. Add inference/mass-assignment/IDOR/caching/audit tests and docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized user receives/changes only allowed records and fields.

## 22. Alternative flow

Masked/read-only or owner/shared/org-scoped access applies deterministically.

## 23. Exception flow

Forbidden filter/sort/export/write/mass assignment or record ID fails without existence leakage.

## 24. Business rules

- Field/record access is server enforced and layered with entitlement/RBAC/RLS.
- Unknown resource/field defaults deny.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Projection/input/filter/sort/export all use the same versioned policy.
- Policy change/revocation invalidates caches.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Cover sensitive finance/HR/bank/credential categories even if domains arrive later.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, owners/non-owners, shared/unshared records, allowed/masked/hidden/read-only fields and inference attempts. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Evaluator/projection/input/record-scope/cache tests.
- REST/GraphQL/search/filter/sort/export/file/IDOR/mass-assignment negatives.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- RBAC/RLS, API serialization, UI metadata, reports and audit.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-114.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- No forbidden field/record leaks or mutates across any integrated path.
- Mask/read-only/owner/share semantics and performance pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

