# Prompt 131 — Import/Export Job Framework

**Prompt ID:** `CG-S6-PLT-028`  
**Package document:** `CG-AABPP-PLT-131`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-131.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-028` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Data Exchange; Epic: Bulk Data Operations; Capability: Async import/export foundation; Feature slice: Staging→validate→preview→commit or generate→signed result; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant/permission-aware asynchronous import/export framework with versioned schemas, row errors, progress and secure files.

## 5. Business value

Enable scalable bulk operations without blocking UI, corrupting data or leaking fields.

## 6. Source requirement

PKG-PLT-IMP-001; import/export framework; file/job/API controls; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Import/export framework schema/migrations/service/adapters/job/file/UI primitives/tests/docs. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Full domain imports/exports, real tenant files, synchronous heavy processing. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Batch/staging/row-error/result/checkpoint records with tenant keys, RLS, retention, constraints and indexes.

## 14. API impact

Template/schema/upload/start/preview/commit/status/cancel/result contracts using async job foundation interface.

## 15. UI/UX impact

Reusable wizard/progress/error/result states; full module imports later.

## 16. Security impact

Scan uploads, field/record/export permissions, formula injection, signed result, retention and no real data logs.

## 17. Performance impact

Streaming/chunking/batching/backpressure/server pagination/bounded memory; heavy work async.

## 18. Audit impact

Requester/schema/version/filters/file hash/class/counts/commit/result/download and privileged retry.

## 19. Data migration impact

Framework only; domain transformations are versioned module adapters and never uncontrolled migration.

## 20. Detailed implementation tasks

1. Define import/export schema adapter, batch states, commit policy, checkpoint/error/result contracts.
2. Implement staging/stream parse/validate/preview/idempotent commit and export generation primitives.
3. Integrate file scan/storage, access projection, signed result, cancel/retry/cleanup.
4. Add example adapter, large-volume/security/reconciliation/tests/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized valid batch processes asynchronously and reconciles canonical result/file.

## 22. Alternative flow

Preview/partial-policy/resume/filter export follows explicit schema/permission.

## 23. Exception flow

Malware/invalid row/duplicate/unauthorized field/timeout/partial failure is contained/actionable.

## 24. Business rules

- No silent coercion/cross-tenant references/client full dataset.
- Domain adapter uses canonical service/validation, not direct unsafe writes.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Schema/version/counts/errors/commit/idempotency/checkpoints reconcile.
- Result access/retention and formula safety enforced.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Request/source fields/rows/staging/errors/result/download each re-authorized.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, valid/mixed/duplicate/large/malicious files, restricted fields, interruptions and filters. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Schema/parser/staging/preview/commit/idempotency/checkpoint/cancel/cleanup tests.
- RLS/RBAC/field/export/malware/formula/signed URL/load/audit tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- File engine, API, jobs, master data and transaction performance.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-131.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Framework is resumable, secure, scalable and adapter-governed.
- No partial corruption/leak/blocking; tests/docs pass.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

