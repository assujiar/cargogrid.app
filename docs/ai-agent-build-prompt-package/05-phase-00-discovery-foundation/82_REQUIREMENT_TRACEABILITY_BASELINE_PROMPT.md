# Prompt 82 — Requirement Traceability Baseline

**Prompt ID:** `CG-S5-PH0-003`  
**Package document:** `CG-AABPP-PH0-082`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-82.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-003` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Governance and Traceability; Epic: Requirement Control; Capability: Requirement-to-architecture/WBS/test mapping; Feature slice: Bootstrap repository traceability matrix; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Create the repository-native requirement traceability baseline linking all decisions, 194 explicit requirements, gap controls, catalogues and WBS tasks.

## 5. Business value

Prevent omitted, duplicated or late requirements and provide deterministic ownership for later phase prompts.

## 6. Source requirement

CTRL-005; ARCH-048..050 runtime outputs; all CPD/RPD/BPR/NFR/catalogue IDs. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Traceability, governance, build-log and validation-script paths explicitly approved. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Application/domain feature code, schemas/data, public contracts and unrelated docs. Always preserve unrelated/user-owned changes.

## 13. Database impact

No schema change; map schema owners/migration tasks where requirements affect data.

## 14. API impact

Map REST/GraphQL/contracts to requirement and later task owners without changing them.

## 15. UI/UX impact

Map portals/routes/flows/WCAG/browser obligations to later task and evidence owners.

## 16. Security impact

Map tenant/RLS/RBAC/field/record/file/secret controls and accepted risks.

## 17. Performance impact

Map explicit and generated performance controls to budgets/evidence owners.

## 18. Audit impact

Trace every mapping change, owner, source and status.

## 19. Data migration impact

Map migration/data-transition obligations; do not implement them.

## 20. Detailed implementation tasks

1. Import/reconcile authoritative requirement inventories and exact totals.
2. Map each item to architecture artifact, Phase 0 or later phase, WBS task, verification/hardening/release evidence and owner.
3. Identify orphan, duplicate, conflict, partial/external and accepted-risk states.
4. Create automated/document validation for totals, IDs and bidirectional links.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Every source requirement has delivery and verification ownership.

## 22. Alternative flow

External legal/SME/contract validation has an explicit gate/owner/date without false implementation coverage.

## 23. Exception flow

Unmapped/conflicting/duplicate item blocks affected downstream task and generates closure action.

## 24. Business rules

- One primary owner per item; cross-phase work uses explicit prerequisite/extension links.
- COVERED requires delivery plus verification evidence owner.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Totals reconcile with 184 functional, 10 explicit NFR and registered package controls/catalogues.
- No WBS task lacks legitimate source.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Trace sensitive/access requirements without exposing protected values.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic matrix fixtures for duplicate/orphan/cycle/partial states. Use synthetic/redacted data only.

## 28. Tests to create/update

- ID uniqueness, count reconciliation, bidirectional link, orphan/duplicate/cycle and status validation.
- Fresh-context requirement lookup test.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Step 0 coverage, architecture WBS, release train and decision registers.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-82.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- All authoritative items are mapped or explicitly blocking/external with owner.
- Traceability is machine-reviewable and no coverage is fabricated.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
