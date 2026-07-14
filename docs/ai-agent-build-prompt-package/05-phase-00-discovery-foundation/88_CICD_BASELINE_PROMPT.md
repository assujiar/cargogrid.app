# Prompt 88 — CI/CD Baseline

**Prompt ID:** `CG-S5-PH0-009`  
**Package document:** `CG-AABPP-PH0-088`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-88.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-009` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: DevOps and Delivery; Epic: Automated Quality Pipeline; Capability: CI baseline and artifact provenance; Feature slice: Repository-aligned pull-request and mainline gates; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the minimum trusted CI/CD baseline using verified package manager/scripts, isolated services and evidence-producing quality gates.

## 5. Business value

Catch regressions before merge and create reproducible artifacts without implying production deployment readiness.

## 6. Source requirement

Delivery/Testing Plan CI gates; DEVOPS workstream; PH0-085..087; GOV quality rules. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Approved CI workflow/config/scripts/tests/docs and bounded tooling configuration. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Production deployment/IaC/secrets, unrelated dependencies, domain code and shared databases. Always preserve unrelated/user-owned changes.

## 13. Database impact

Use disposable CI DB only; migration rebuild/upgrade/seed/RLS jobs are isolated and non-production.

## 14. API impact

Run contract/schema compatibility checks where existing contracts exist.

## 15. UI/UX impact

Run build/component/accessibility/browser smoke only with installed supported tooling.

## 16. Security impact

Secret-safe CI permissions, dependency/secret scanning, untrusted-fork controls and no production credentials.

## 17. Performance impact

Cache safely by lockfile/environment; measure pipeline duration without skipping required gates.

## 18. Audit impact

Capture commit, workflow version, artifact checksum/provenance, gates and approvals.

## 19. Data migration impact

CI validates migrations on clean and supported upgrade paths; never edits/applies to shared DB.

## 20. Detailed implementation tasks

1. Inventory existing workflows/scripts/services and preserve credible brownfield jobs.
2. Implement deterministic install, lint, typecheck, unit/integration/build and applicable migration/security/accessibility gates.
3. Add artifact/test-report evidence, cache isolation, concurrency/cancellation, timeouts and failure visibility.
4. Document required/optional gates, branch triggers, local parity, recovery and future deployment separation.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

PR/mainline runs trusted mandatory gates and publishes traceable evidence.

## 22. Alternative flow

Scoped job matrix/changed-package optimization preserves mandatory affected coverage.

## 23. Exception flow

Missing tool/service/secret, flaky gate or pre-existing failure is visible and blocks according to policy.

## 24. Business rules

- No hidden failure, continue-on-error for mandatory gates or test weakening.
- CI baseline is not production deployment authorization.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Workflow uses verified package manager/lockfile/scripts and least-privilege permissions.
- Artifacts/results are tied to exact commit and environment.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- CI secrets/environments/approvals are scoped; forked code cannot exfiltrate secrets.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic isolated fixtures/services; no live tenant or production database. Use synthetic/redacted data only.

## 28. Tests to create/update

- Workflow syntax, clean install/build, cache miss/hit, failure visibility and artifact provenance.
- Migration/RLS/secret/fork permission negatives as applicable.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing CI triggers, contributor workflow, package scripts and local parity.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-88.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Mandatory baseline gates run reproducibly and fail visibly at exact commit.
- No production credential/service/deployment mutation is introduced.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
