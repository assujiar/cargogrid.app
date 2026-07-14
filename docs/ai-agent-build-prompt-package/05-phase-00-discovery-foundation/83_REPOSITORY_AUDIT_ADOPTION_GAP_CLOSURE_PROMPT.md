# Prompt 83 — Repository Audit Adoption and Gap Closure

**Prompt ID:** `CG-S5-PH0-004`  
**Package document:** `CG-AABPP-PH0-083`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-83.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-004` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Repository Foundation; Epic: Brownfield Baseline Adoption; Capability: Verified discovery integration; Feature slice: Adopt discovery findings into implementation controls; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Adopt verified Step 2 repository evidence into persistent ownership, debt, baseline and gap controls without re-running unsafe discovery or fixing unrelated defects.

## 5. Business value

Anchor Phase 0 changes to the actual brownfield repository and separate pre-existing failures from new regressions.

## 6. Source requirement

DISC-021..034 runtime outputs; approved strategy decision; debt/risk register. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Discovery-derived context/status/issues/WBS/build-log documentation and validation scripts. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Application/tests/config/migrations/data/dependencies/services/deployments. Always preserve unrelated/user-owned changes.

## 13. Database impact

Record verified schema/migration state and trust; no migration/database write.

## 14. API impact

Record actual route/REST/GraphQL/module contracts and evidence gaps.

## 15. UI/UX impact

Record actual routes/components/accessibility baseline and placeholder/dead surfaces.

## 16. Security impact

Adopt security findings, critical blockers and evidence limitations without active exploitation.

## 17. Performance impact

Adopt measured/static/not-run baseline and reproducibility metadata.

## 18. Audit impact

Preserve evidence IDs/checkpoint/redaction and gap ownership.

## 19. Data migration impact

No data migration; create future task links only.

## 20. Detailed implementation tasks

1. Verify Step 2 evidence remains current at the active checkpoint and classify drift.
2. Adopt repository/toolchain/schema/routes/security/test/performance/UX/debt inventories into context, status, issues and WBS.
3. Assign each unresolved finding to Phase 0 task, later phase, ADR, external gate or accepted risk.
4. Define baseline comparison and stale-evidence triggers for subsequent tasks.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Every verified discovery finding has durable ownership/status and downstream task mapping.

## 22. Alternative flow

Stale evidence is safely refreshed through the exact Step 2 prompt before adoption.

## 23. Exception flow

Checkpoint drift, contradiction, untrusted DB/repo or critical blocker stops Phase 0.

## 24. Business rules

- Discovery findings are evidence, not permission to quick-fix.
- Preserve approved greenfield/brownfield strategy and valuable assets.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Evidence IDs/checkpoints/counts and adopted registers reconcile.
- Pre-existing failure remains distinguishable from regression.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Keep sensitive security details audience-restricted and redacted.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

No real data; use discovery metadata and synthetic validation fixtures. Use synthetic/redacted data only.

## 28. Tests to create/update

- Checkpoint/staleness, evidence-link, finding-owner/status and baseline classification validation.
- Forbidden-change worktree comparison.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Original discovery artifacts, debt/risk register and persistent ledgers.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-83.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- All discovery evidence is adopted or explicitly stale/blocked with resume prompt.
- No feature/fix/schema/environment mutation occurs.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
