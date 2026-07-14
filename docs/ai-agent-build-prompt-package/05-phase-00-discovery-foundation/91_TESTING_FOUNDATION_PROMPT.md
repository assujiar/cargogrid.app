# Prompt 91 — Testing Foundation

**Prompt ID:** `CG-S5-PH0-012`  
**Package document:** `CG-AABPP-PH0-091`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-91.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-012` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Quality Engineering; Epic: Automated Evidence; Capability: Layered test architecture; Feature slice: Deterministic frameworks, fixtures and baseline gates; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the repository-aligned testing foundation for unit, integration, database/RLS, contract, component, E2E, accessibility and performance evidence.

## 5. Business value

Make later feature work verifiable and regressions attributable from a trusted baseline.

## 6. Source requirement

Testing workstream; verified test baseline; Master Prompt §15–16; delivery gates. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Approved test config/harness/factory/fixture/example/docs and CI integration paths. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Domain feature changes, real data/secrets, shared DB, test weakening and unrelated snapshots. Always preserve unrelated/user-owned changes.

## 13. Database impact

Provide disposable DB harness, migration/constraint/RLS fixtures and cleanup without shared/live DB.

## 14. API impact

Provide contract/service test harness for REST/GraphQL parity and idempotency.

## 15. UI/UX impact

Provide component/E2E/accessibility harness for complete states and supported browsers when tooling exists.

## 16. Security impact

Synthetic multi-tenant identities, cross-tenant negatives, secrets isolation and safe test logs.

## 17. Performance impact

Separate correctness CI from representative benchmark/load environments; define reproducible budgets.

## 18. Audit impact

Tests/evidence tied to requirement/task/checkpoint; skipped/flaky/quarantine visible.

## 19. Data migration impact

Support clean rebuild/upgrade/data preservation tests using disposable environments.

## 20. Detailed implementation tasks

1. Reconcile existing frameworks/configs/fixtures and preserve credible brownfield tests.
2. Implement shared deterministic factories/fixtures for tenants/orgs/roles and foundation harnesses at approved layers.
3. Define test naming/tags/environments/artifacts, isolation/cleanup, flake/quarantine and baseline comparison.
4. Add smoke examples proving each configured layer and integrate safe gates into CI.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Developer runs scoped and mandatory suites deterministically with traceable results.

## 22. Alternative flow

Unavailable expensive layer is explicitly NOT_RUN with owned environment gate, never falsely passed.

## 23. Exception flow

Flake/leak/shared DB/secret exposure or non-determinism blocks foundation closure.

## 24. Business rules

- Tests validate behavior/control, not implementation trivia; never disable to pass.
- Two-tenant negative evidence is mandatory for tenant paths.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Fixtures are isolated/repeatable and test results include counts/duration/artifacts.
- Baseline failures are classified separately from regressions.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Test identities cover roles/scopes/field/record/support and no privileged default bypass.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Deterministic synthetic two-tenant canonical foundation fixtures; privacy-safe edge cases. Use synthetic/redacted data only.

## 28. Tests to create/update

- Meta-tests for fixture isolation/cleanup, runner/config/artifacts and sample layer gates.
- Cross-tenant, migration rebuild, API/component/E2E/accessibility/performance harness smoke.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing suites/snapshots/CI commands and critical discovery baseline.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-91.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Configured test layers run reproducibly or are explicitly gated with owner.
- No shared data leak, hidden skip/failure or weakened baseline.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
