# Prompt 84 — ADR Baseline and Decision Governance

**Prompt ID:** `CG-S5-PH0-005`  
**Package document:** `CG-AABPP-PH0-084`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-84.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-005` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Architecture Governance; Epic: Decision Records; Capability: ADR repository and lifecycle; Feature slice: Bootstrap approved architecture decision mechanism; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Create the repository-native ADR framework and resolve only Phase 0 technical decisions supported by verified evidence and authorized approvers.

## 5. Business value

Keep architecture changes explainable, reviewable and reversible without silently changing product policy.

## 6. Source requirement

ARCH-035..051 runtime outputs; ADR_REQUIRED items; Step 0 decision/conflict registers. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

ADR/index/governance/traceability/build-log paths and validation scripts. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Runtime source/config/schema/data/deployment changes. Always preserve unrelated/user-owned changes.

## 13. Database impact

Record schema/migration ADRs; no DDL/data change.

## 14. API impact

Record contract/versioning decisions; no endpoint change.

## 15. UI/UX impact

Record design/portal decisions; no UI change.

## 16. Security impact

Threat/access/security ADRs require security impact and cannot weaken protected controls.

## 17. Performance impact

Record budgets/trade-offs and evidence; no speculative claims.

## 18. Audit impact

ADR lifecycle is append-only with status, approver, supersession and propagation.

## 19. Data migration impact

ADR may authorize later migration task but does not execute it.

## 20. Detailed implementation tasks

1. Create ADR template/index/status vocabulary and authority boundaries.
2. Reconcile runtime architecture ADR candidates and distinguish approved, proposed, blocked and rejected.
3. Draft/approve only bounded Phase 0 ADRs with options, evidence, trade-offs, migration/rollback and downstream impacts.
4. Propagate approved ADR references to WBS/traceability/context without rewriting protected CPD/RPD decisions.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Authorized technical decision is documented, approved and propagated before dependent implementation.

## 22. Alternative flow

Decision remains proposed/blocked with explicit evidence/approver needed.

## 23. Exception flow

Product-policy conflict, insufficient runtime evidence or missing authority stops the ADR.

## 24. Business rules

- Recommendation is not approval; CPD/RPD changes require formal product change control.
- Supersession preserves history; no silent edit.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Each ADR has unique ID, question/options/decision/evidence/owner/status/effects/rollback.
- No dependent task is READY before required ADR approval.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Sensitive security/deployment detail is redacted or access-controlled.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic ADR lifecycle and supersession examples only. Use synthetic/redacted data only.

## 28. Tests to create/update

- ADR schema/ID/status/link/supersession validation and missing-approval gate test.
- Traceability propagation check.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Decision/conflict/assumption registers and architecture outputs.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-84.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- ADR framework is usable and required Phase 0 decisions are approved or explicitly blocking.
- No product policy or runtime behavior changes.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
