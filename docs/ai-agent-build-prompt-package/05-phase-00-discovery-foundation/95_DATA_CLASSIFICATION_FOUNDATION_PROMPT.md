# Prompt 95 — Data Classification Foundation

**Prompt ID:** `CG-S5-PH0-016`  
**Package document:** `CG-AABPP-PH0-095`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-95.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-016` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Data Governance and Security; Epic: Information Protection; Capability: Canonical data classification; Feature slice: Classification taxonomy, registry and handling controls; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a repository-native classification system for CargoGrid data, fields, files, logs, exports and analytics with owners and handling rules.

## 5. Business value

Make access, masking, retention, audit and incident decisions consistent before sensitive domain data is implemented.

## 6. Source requirement

UX/Data/Access Design; Technical Architecture data classification; retention RPD-025; RPD-022. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Classification registry/docs/validation/tests and approved metadata hooks. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Business data rewrite, broad schema/API/UI feature changes, real sensitive samples. Always preserve unrelated/user-owned changes.

## 13. Database impact

Classify known/future schema fields and policy implications; no broad schema change.

## 14. API impact

Define request/response/log/export classification and redaction metadata expectations.

## 15. UI/UX impact

Define display/mask/copy/download/error/analytics handling by audience and portal.

## 16. Security impact

Primary scope: public/internal/confidential/restricted/credential plus PII/finance/payroll/tax/bank categories and controls.

## 17. Performance impact

Classification lookup/metadata must not create per-row N+1; compile/cache safely.

## 18. Audit impact

Classification changes, owner, effective date and privileged restricted access are auditable.

## 19. Data migration impact

Existing metadata/backfill requires separately bounded task; do not transform business data here.

## 20. Detailed implementation tasks

1. Reconcile source classifications, regulatory/contractual needs and current repository fields/files/logs.
2. Define taxonomy, handling matrix, owner, retention/legal-hold, masking, encryption, export, logging and incident rules.
3. Create registry/schema/annotations or documentation mechanism aligned with architecture and current codebase.
4. Classify Phase 0 assets and define adoption/validation gates for later schema/API/UI prompts.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

A data element receives one governed classification and deterministic handling requirements.

## 22. Alternative flow

Multiple sensitivities resolve to the strongest applicable handling with documented rationale.

## 23. Exception flow

Unknown/conflicting/unowned classification blocks exposure/export/logging until resolved.

## 24. Business rules

- Supreme Admin absolute CRUD can defeat retention evidence and must remain disclosed.
- Legal hold overrides deletion; least exposure and purpose limitation apply.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Every Phase 0 data/file/log class has owner and handling matrix.
- Registry links to schema/API/UX/security/retention controls.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Classification determines field/record/export/report/support access and masking, not role name alone.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic field/file/log examples across all classes, including mixed/derived data. Use synthetic/redacted data only.

## 28. Tests to create/update

- Taxonomy/registry schema, strongest-rule precedence, missing-owner/classification and redaction validation.
- Export/log/telemetry sensitive marker negative tests.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing data dictionaries, schema registry, API docs, observability and retention rules.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-95.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Classification taxonomy/registry/handling rules are complete and enforceable for later prompts.
- No sensitive content is exposed or silently left unclassified.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
