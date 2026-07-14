# Prompt 100 — Phase 0 Hardening

**Prompt ID:** `CG-S5-PH0-021`  
**Package document:** `CG-AABPP-PH0-100`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-100.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-021` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Phase Hardening; Epic: Foundation Risk Reduction; Capability: Close Phase 0 residual control gaps; Feature slice: Evidence-ranked bounded hardening; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Close verified Phase 0 residual gaps from Prompt 99 using bounded tasks without introducing new capabilities.

## 5. Business value

Reduce foundation risk to the Phase 1 entry threshold.

## 6. Source requirement

PH0-099 verification report; threat model; debt/risk/error/issues registers. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Exact finding-linked foundation source/config/tests/docs/migrations approved in hardening plan. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

New domain features, unrelated debt/refactor, production mutation and gate suppression. Always preserve unrelated/user-owned changes.

## 13. Database impact

Only approved foundation repair migrations, normally 1–3, with full rebuild/upgrade/recovery evidence.

## 14. API impact

Harden existing foundation contracts only; no new domain endpoint.

## 15. UI/UX impact

Harden foundation components/states/accessibility only; no feature redesign.

## 16. Security impact

Prioritize critical/high tenant/secret/session/input/file/control gaps and negative tests.

## 17. Performance impact

Close measured foundation regressions/overhead only with before/after proof.

## 18. Audit impact

Record each finding→repair→test→closure/residual acceptance link.

## 19. Data migration impact

Repair/backfill requires idempotent bounded migration/data task and reconciliation.

## 20. Detailed implementation tasks

1. Rank Prompt 99 findings by criticality/dependency and split into atomic repair IDs.
2. Resolve only authorized Phase 0 blockers within exact files and approved sequence.
3. Run root-cause negative/regression/integration tests and baseline comparisons.
4. Re-run Prompt 99 affected/full mandatory gates and reconcile risks/issues/docs.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Each critical/high Phase 0 finding is closed with reproducible evidence.

## 22. Alternative flow

Non-critical residual risk has authorized owner/expiry/monitoring and cannot block mandatory gate.

## 23. Exception flow

Unknown root cause, integrity loss, unsafe migration or scope expansion blocks hardening and creates recovery prompt.

## 24. Business rules

- No new capability or cosmetic cleanup; fix root cause, not test symptoms.
- Critical tenant/security/data/CI blocker cannot be accepted for Phase 1.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Every change maps to Prompt 99 finding and acceptance evidence.
- No suppression/weakened gate or unrelated file change.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Repair preserves or strengthens least privilege and tenant isolation.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Exact synthetic reproducers plus integrated Phase 0 fixtures. Use synthetic/redacted data only.

## 28. Tests to create/update

- Finding-specific failing-before/passing-after tests and full affected integration.
- Mandatory secret/security/tenant/performance/docs/CI regression.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- All Prompt 81–99 verified foundations and clean environment setup.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-100.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- All mandatory blockers close and integrated verification re-passes.
- Residual risks are non-critical, authorized and visible.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.

