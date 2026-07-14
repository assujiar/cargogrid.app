# Prompt 87 — Git Strategy Foundation

**Prompt ID:** `CG-S5-PH0-008`  
**Package document:** `CG-AABPP-PH0-087`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-87.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-008` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Developer Workflow; Epic: Change Isolation and Review; Capability: Repository Git operating model; Feature slice: Branch/commit/review/recovery policy and checks; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement repository-specific Git strategy documentation and safe checks for atomic branches, review, protected paths and checkpoint recovery.

## 5. Business value

Make changes traceable/reviewable and prevent branch history or user work from being damaged.

## 6. Source requirement

Delivery plan; GOV-010..019; verified repository topology; release train. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Git/contributor/governance docs and approved non-destructive validation configuration/tests. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

History rewrite, commit/push/PR, unrelated CI, source/schema/data changes. Always preserve unrelated/user-owned changes.

## 13. Database impact

Define migration commit/order/review rules; no migration change.

## 14. API impact

Define compatibility/review ownership for contract changes.

## 15. UI/UX impact

Define screenshot/accessibility evidence expectations for UI review.

## 16. Security impact

Protect secret files, security reviews and signed/verified provenance where supported.

## 17. Performance impact

No runtime effect; keep checks fast and scoped.

## 18. Audit impact

Branch/commit/PR/task/change-manifest linkage is mandatory.

## 19. Data migration impact

Applied migration immutability and sequential review rules are explicit.

## 20. Detailed implementation tasks

1. Inspect actual hosting/branch/protection/workspace conventions and existing CI integration.
2. Define atomic branch naming, commit/task linkage, review/approval, merge strategy, protected paths and release/hotfix flow.
3. Define dirty-worktree ownership, checkpoint, conflict, rollback/revert and interrupted-task recovery.
4. Add non-destructive validation hooks/checks only where authorized and document exceptions.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

One atomic task moves from READY branch to reviewed verified merge with traceable evidence.

## 22. Alternative flow

Hotfix/recovery branch follows recorded emergency authority and follow-up reconciliation.

## 23. Exception flow

Overlapping user changes, protected path, failed gate or unknown migration blocks merge and preserves work.

## 24. Business rules

- No force push/history rewrite/destructive reset without explicit authority.
- One task/branch/objective; oversized work is split.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Policy matches actual repository capabilities and does not invent unavailable protection.
- Branch/commit/task/change/evidence references reconcile.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Merge/release/security/migration approvals have least-privilege ownership.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic branch/commit/PR naming and protected-path cases. Use synthetic/redacted data only.

## 28. Tests to create/update

- Policy/schema/lint validation, branch-name/task-link and protected-path negative tests if automated.
- Recovery drill documentation review.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing contributor workflow, CI triggers, release/hotfix and user-owned changes.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-87.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Git workflow is actionable, repository-aligned and protects atomic checkpoints.
- No branch/history/external repository mutation occurs without separate authority.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
