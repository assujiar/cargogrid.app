# Prompt 240 — Label and Barcode Operations

**Prompt ID:** `CG-S10-ATW-021`  
**Package document:** `CG-AABPP-ATW-240`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-240.md`

Do not begin until Prompt 220 marks this task `READY`, all variables are resolved, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-021` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Warehouse Execution; Epic: Scan and Identification; Capability: Label and Barcode Operations; Feature slice: governed templates, encoded identifiers, print jobs, scan resolution, reprint/void and lineage; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement secure, traceable label generation, printing and scan resolution across warehouse tasks without treating a barcode as authorization.

## 5. Business value

Accelerate accurate physical execution while reducing misidentification and uncontrolled reprints.

## 6. Source requirement

OPS-WMS-001..004 scan/label slice and RPD-032. Cite exact source sections, runtime evidence, template/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closure IDs, schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read all persistent ledgers and build/handoff logs plus source requirements. Inspect warehouse identities, scanning, printing/files, APIs/UI/jobs and tests; run feasible baselines, state plan/expected files, and stop on scope/security/data/phase-boundary conflict.

## 9. Upstream dependencies

ATW-229..239, especially canonical bin, task, package and stock identities. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

ATW-241..248. Identify affected templates, identifiers, tasks, devices/printers, REST/GraphQL, jobs/files, audit, tests, docs and consumers.

## 11. Allowed files/folders

Use only exact Advanced WMS schema, migration, service, UI, job/integration, test and documentation paths authorized by the WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity roots, native/offline client, full Step 11–14 implementations, tenant forks, applied-migration edits, destructive cleanup, test/permission weakening and unrelated user changes.

## 13. Database impact

Add label template/version/scope, whitelisted variables, label instance/encoded identifier, subject lineage, print/reprint/void job, printer target, outcome/error and scan-resolution evidence.

## 14. API impact

Shared REST/GraphQL template read, preview, generate, print, reprint, void, job-status and authorized resolve/scan operations with one service, auth, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Template list/preview, task-level print action, printer/job queue and scan feedback. Include loading, empty, error, success, permission-denied, stale-template and degraded-printer states; responsive online-first PWA, accessible keyboard/manual alternative and no dead action.

## 16. Security impact

Template/printer/subject scope, least-data label content, injection-safe rendering and private artifacts where sensitive. Encoded IDs are references, never credentials; every resolution reauthorizes tenant/customer/warehouse/record access. Preserve RLS/RBAC and server-only secrets.

## 17. Performance impact

Index tenant/template/version/subject/status/job/printer/date; batch-print through bounded durable jobs with backpressure and idempotency. Use cursor lists, selective queries and limited realtime; measure queue latency/throughput and avoid browser-loaded datasets.

## 18. Audit impact

Record template/version, allowed variables, subject, encoded value digest where appropriate, printer, actor, copies, print/reprint/void reason, job attempt/result and scan resolution. Include correlation/idempotency and source lineage.

## 19. Data migration impact

Register only evidenced active templates/identifiers and do not silently re-encode historic labels. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse compatibility, backup and rollback.

## 20. Detailed implementation tasks

- Inventory subjects, current codes, templates and printer integrations.
- Define identifier uniqueness/scope/checksum, template/version and reprint/void rules.
- Implement rendering, durable print jobs, APIs and accessible scan/print UX.
- Reauthorize every scan and minimize label data.
- Test injection, duplication, retries, scope, throughput and recovery.

## 21. Main flow

Authorized user selects a governed template and subject, service validates/version-renders the label, durable job prints it once, and later scan resolves the subject only after current authorization.

## 22. Alternative flow

Preview without printing, batch-print bounded tasks, choose an approved printer, use manual entry, or reprint with a governed reason while retaining lineage.

## 23. Exception flow

Block unknown/duplicate/void code, wrong subject/scope, unsafe variable, stale template, unauthorized printer, job timeout, duplicate retry or ambiguous scan. Preserve job evidence and safe retry/resume.

## 24. Business rules

- Template variables are whitelisted, escaped, versioned and scope-bound.
- Barcode uniqueness and format/checksum rules are deterministic; code possession grants no access.
- Reprint and void preserve original lineage and require policy/reason.
- Extend canonical Phase 3/4 records; do not duplicate subject truth.
- Printing is online-first with durable jobs; no native/offline sync or silent client-only success.
- RPD-022 prevents tamper-proof/immutable-for-all claims; no tenant fork, autonomous AI or partial-GA claim.

## 25. Validation rules

- Template/version, subject, printer and variables are active, compatible and authorized.
- Encoded identity resolves uniquely inside its allowed scope.
- Reject tenant/customer-owner/warehouse/subject/version mismatch, stale mutation and unsafe content.
- Every generate/print/reprint/void/resolve action is idempotency-safe and source-reconcilable.

## 26. Access rules

Warehouse staff print task labels; supervisors govern reprint/void; admins govern templates/printers; customer users resolve only permitted subjects. Enforce database/service authorization for every path, including export/realtime.

## 27. Test data requirement

Bin/item/lot/serial/package/pallet/task labels, Unicode/long values, void/reprint, printer failure, duplicate retry, forged/foreign code and Tenant A/B owner fixtures with allowed/denied roles.

## 28. Tests to create/update

- Template/version/escaping/identifier uniqueness and job-idempotency tests.
- Authorized/denied scan resolution, forged-code and cross-tenant/customer tests.
- Printer retry/backpressure/load, migration and accessibility/manual-entry tests.
- Critical inbound→outbound scan-flow E2E under RPD-032.

## 29. Regression tests

Inbound, putaway, inventory, picking, packing, outbound, dispatch/package documents and future portal. Re-run isolation, API compatibility, job, browser/accessibility and critical E2E suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository lint/typecheck/test/build plus database migration/type generation, security, template snapshot, job/integration, target-volume batch-print and scan E2E commands. Never disable a gate.

## 31. Documentation to update

Template/identifier/printer/reprint/void/scan contract, supported symbologies and printer/job recovery runbook. Update persistent status/task/decision/error/issue/traceability/schema/API/build-log and user/admin/support docs.

## 32. Rollback/recovery note

Stop new jobs, drain/cancel only safe pending attempts, preserve printed/void lineage and restore compatible template routing. State checkpoint, reconciliation and resume; do not destructively delete history.

## 33. Acceptance criteria

- Governed labels print and resolve end to end with current authorization.
- Retries do not create untraceable duplicate jobs/identities.
- Reprint/void and printer failures are auditable and recoverable.
- Mandatory gates pass at one checkpoint with source-to-evidence mapping.

## 34. Definition of Done

No placeholder/fake persistence/dead action; migrations, types, RLS/RBAC, shared APIs, complete UX, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical security/operations blocker remains.

## 35. Completion report format

Report IDs/checkpoint; changed files/contracts/templates; commands/results; label/scan, tenant/access, job/idempotency/performance evidence; residual risks; docs; rollback/resume; next task. Update all ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-241 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
