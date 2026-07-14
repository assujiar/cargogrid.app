# Template 61 — Import and Export

**Prompt ID:** `CG-S4-REUSE-009`  
**Package document:** `CG-AABPP-REUSE-061`  
**Version:** `0.5.0`  
**Intended use:** Implement one permission-aware asynchronous import or export pipeline.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Import, Export and Data Exchange.

## 4. Objective

Implement {{IMPORT_OR_EXPORT_SLICE}} with staging, validation, authorization, progress, audit and resumable evidence.

## 5. Business value

Move tenant data safely at scale without blocking UI, leaking fields or corrupting canonical records.

## 6. Source requirement

{{DATA_EXCHANGE_REQUIREMENT_IDS}}, {{SCHEMA_CONTRACT_ID}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`, approved ADRs/migrations/contracts, verified runtime gates and baseline evidence. All must be satisfied or explicitly blocking.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; normally 5–15 files, one module boundary and at most 1–3 approved migrations. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, lockfiles unless dependency scope is explicit, secrets, generated artifacts unless authorized, tenant data, and broad refactors.

## 13. Database impact

Use tenant-scoped staging/batch/error/result records, canonical transaction boundaries, constraints, cleanup and retention.

## 14. API impact

Define upload/start/status/error/result/download contracts with schema version and idempotency.

## 15. UI/UX impact

Provide template/schema guidance, upload/configuration, validation preview, progress, row errors, retry/cancel and result states.

## 16. Security impact

Malware-scan uploads; enforce file/field/record/export permission, formula injection protection, signed download and retention.

## 17. Performance impact

Async processing, streaming/chunking, server pagination, bounded memory, batch writes and backpressure.

## 18. Audit impact

Audit requester, tenant, schema/version, filters, row counts, file hash/classification, outcome and download access.

## 19. Data migration impact

Import is not an uncontrolled migration; transformations are versioned/idempotent and canonical validation applies.

## 20. Detailed implementation tasks

1. Define versioned input/output schema, permissions, limits and retention.
2. Implement scan/quarantine, staging, parsing/streaming, row/batch validation, preview and commit or export generation.
3. Implement idempotency, partial/atomic policy, progress, row errors, retry/cancel, cleanup and signed result.
4. Add large-volume, security, reconciliation, observability and support documentation.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Authorized user processes a valid file/filter and receives reconciled canonical result.

## 22. Alternative flow

Partial-validation preview, resumable batch or filtered export completes according to explicit policy.

## 23. Exception flow

Malware, invalid schema/row, duplicate, unauthorized field/record, size limit, timeout and partial failure remain contained.

## 24. Business rules

- No silent coercion, cross-tenant reference or client-side full dataset.
- Export schema/version and import commit policy are explicit.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Header/type/enum/reference/business/concurrency and aggregate counts reconcile.
- Spreadsheet formula injection and dangerous file content are neutralized.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Check request, source rows/fields, staging/errors and signed result on every access.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Two tenants, valid/invalid/mixed/duplicate/large files, malicious formulas/content, unauthorized fields and concurrent batches. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Parser/schema/business, staging/commit/rollback, permission and cross-tenant tests.
- Malware/quarantine, formula injection, async job, retry/cancel, large-volume and signed-download tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Canonical create/update flows, exports consumers, storage retention, jobs and database load.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Valid data reconciles and invalid data is actionable without partial corruption.
- Security, scale, audit, cleanup and authorization evidence passes.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
