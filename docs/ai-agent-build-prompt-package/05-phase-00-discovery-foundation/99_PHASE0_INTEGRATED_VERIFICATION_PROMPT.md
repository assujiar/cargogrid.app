# Prompt 99 — Phase 0 Integrated Verification

**Prompt ID:** `CG-S5-PH0-020`  
**Package document:** `CG-AABPP-PH0-099`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-99.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-020` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Phase Verification; Epic: Foundation Integration Gate; Capability: Cross-foundation verification; Feature slice: Integrated evidence and dependency validation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Verify Prompts 81–98 together at one checkpoint and prove the foundations operate consistently without domain feature scope.

## 5. Business value

Catch cross-control gaps before hardening and Platform Core implementation.

## 6. Source requirement

PH0-081..098 build logs; Phase 0 WBS/traceability; test/release gates. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Verification tests/scripts/logs/docs and exact bounded repair only if explicitly part of a prior task (default no repair). Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

New features, broad refactor, production/shared services/data, hidden gate changes. Always preserve unrelated/user-owned changes.

## 13. Database impact

Verify current migration/schema trust, disposable setup and no unauthorized DB changes.

## 14. API impact

Verify environment/standards/security/observability/analytics/flags contracts interoperate.

## 15. UI/UX impact

Verify design/test/security/environment foundation integration and accessibility smoke.

## 16. Security impact

Run secret/tenant/security negative evidence and threat/control linkage.

## 17. Performance impact

Compare setup/build/test/observability/analytics/flag overhead to baseline.

## 18. Audit impact

Reconcile all task/change/decision/error/issues/evidence and accepted-risk disclosures.

## 19. Data migration impact

Verify clean local/CI DB setup and migration history; no production/shared writes.

## 20. Detailed implementation tasks

1. Freeze checkpoint and collect all Prompt 81–98 outputs/commands/artifacts.
2. Run integrated local/CI foundation setup, build, tests, validation and cross-control scenarios.
3. Check requirement/WBS/ADR/docs links, allowed-scope audit, baseline deltas and stale evidence.
4. Create failure matrix and exact recovery tasks; do not fix outside this verification prompt.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Clean environment validates all foundations and produces consistent evidence.

## 22. Alternative flow

Unavailable non-critical external service uses safe disabled/mock path with owned later gate.

## 23. Exception flow

Critical cross-control, tenant/security/data, CI, secret or checkpoint failure blocks hardening.

## 24. Business rules

- Verification does not expand implementation scope or hide failures.
- Passing isolated tasks does not imply integrated pass.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- All task outputs share checkpoint/version and mandatory gates/results reconcile.
- Zero orphan requirement/task/doc/control and zero unauthorized change.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Verification identities/environments are synthetic, least privilege and isolated.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Phase 0 synthetic fixtures, two tenants, invalid env, security abuse, telemetry/analytics/flag failure states. Use synthetic/redacted data only.

## 28. Tests to create/update

- Full foundation lint/type/test/build/CI-equivalent and clean setup.
- Cross-control secret, tenant, docs/traceability, observability, analytics, flags, accessibility and performance checks.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Step 2–4 runtime evidence and every Prompt 81–98 acceptance suite.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-99.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Integrated foundation evidence passes at one checkpoint or exact blockers are recorded.
- No domain feature or external production mutation occurred.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
