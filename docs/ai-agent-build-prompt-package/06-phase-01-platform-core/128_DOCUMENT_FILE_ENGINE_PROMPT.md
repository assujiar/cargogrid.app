# Prompt 128 — Document and File Engine

**Prompt ID:** `CG-S6-PLT-025`  
**Package document:** `CG-AABPP-PLT-128`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-128.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-025` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Platform Engines; Epic: Secure Content Management; Capability: Private document/file foundation; Feature slice: Upload→scan/quarantine→authorize→signed delivery→retention; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement tenant/record-aware private file/document primitives with mandatory malware scanning before availability.

## 5. Business value

Securely support ePOD, contracts, invoices, HR and other later files without public leakage.

## 6. Source requirement

PKG-NFR-FILE-001; document engine; storage/security/retention decisions; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Document/file metadata schema/migrations/service/storage/scan adapter/upload UI/tests/docs/runbook. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Public bucket/default URLs, scan bypass, real sensitive files, domain document workflows. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

File/document metadata, classification, tenant/record owner, version/status, scan result, retention/legal hold and RLS.

## 14. API impact

Initiate/upload-complete/status/authorize/signed-download/version/delete-request contract; size/type limits.

## 15. UI/UX impact

Reusable upload/progress/scan/error/quarantine/available/download/version states; no domain page.

## 16. Security impact

Private-by-default, malware scan/quarantine, MIME/content validation, signed short expiry, no path traversal/IDOR, server credentials only.

## 17. Performance impact

Streaming/direct safe upload, bounded size/concurrency, async scan/generation and cleanup.

## 18. Audit impact

Upload/version/scan/quarantine/release/access/download/delete/hold and privileged actions.

## 19. Data migration impact

Map existing objects/metadata and scan status explicitly; unknown legacy files remain quarantined/restricted.

## 20. Detailed implementation tasks

1. Define document/file metadata, ownership, classification, version, scan and retention lifecycles.
2. Implement secure upload/storage key, validation and scan/quarantine/release workflow.
3. Implement record/field-aware authorization and short-lived signed delivery.
4. Add retention/legal hold/cleanup, legacy strategy, abuse/performance/tests/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Authorized user uploads valid file; scan passes; permitted user receives short-lived access.

## 22. Alternative flow

New version or pending scan is visible with safe status; legal hold preserves object.

## 23. Exception flow

Malware/invalid type/oversize/scan failure/unauthorized access/expired URL remains blocked.

## 24. Business rules

- Every upload is scanned before another user can access it.
- Private file access requires tenant+record+field/permission, not possession of path.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Storage key unguessable/tenant-safe; metadata/object/scan/retention states reconcile.
- Signed URL expiry/content disposition/cache controls correct.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Uploader, record readers, sensitive field roles, support and Supreme paths explicitly tested/audited.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, valid/malicious/spoofed/oversize files, versions, scan timeout, legal hold and expired URLs. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Lifecycle/metadata/object/version/scan/quarantine/retention tests.
- RLS/RBAC/record/field/IDOR/path/MIME/malware/signed URL/cross-tenant/load tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Storage config, auth/access, jobs, audit, future ePOD/docs and backup scope.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-128.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- No file becomes available before clean scan and authorized record access.
- Lifecycle/retention/signed URL/abuse/performance evidence passes.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

