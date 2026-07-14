# Prompt 89 — Coding Standards and Architecture Enforcement

**Prompt ID:** `CG-S5-PH0-010`  
**Package document:** `CG-AABPP-PH0-089`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-89.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-010` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Engineering Quality; Epic: Maintainability Controls; Capability: Repository coding and boundary standards; Feature slice: Documented and automated foundation rules; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement repository-specific coding standards and automated checks that enforce approved boundaries, correctness and safe contribution.

## 5. Business value

Reduce inconsistent code and architecture drift before domain modules scale.

## 6. Source requirement

Master Prompt §§8–21; target repository structure; domain boundary map; ADR baseline. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Standards/docs, existing lint/type/architecture config, rule tests and approved scripts. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Broad code formatting/refactor, feature changes, schema/data, unrelated dependency upgrades. Always preserve unrelated/user-owned changes.

## 13. Database impact

Define migration/query/tenant-key/transaction conventions; no schema change.

## 14. API impact

Define shared domain service, REST/GraphQL contract/error/pagination/versioning conventions.

## 15. UI/UX impact

Define TypeScript/component/server-client/design-system/accessibility/state conventions.

## 16. Security impact

Ban unsafe secrets/client service role, raw bypasses, unvalidated input and unauthorized data access.

## 17. Performance impact

Ban SELECT *, unbounded reads/full browser data/N+1; require measurement for optimization.

## 18. Audit impact

Standards changes and exceptions require owner/ADR/expiry/evidence.

## 19. Data migration impact

Applied migration immutability and additive/expand-contract patterns are enforced.

## 20. Detailed implementation tasks

1. Inventory current style/lint/type/build/architecture checks and compatibility constraints.
2. Document normative coding, naming, module/import, error, logging, test, migration, API and UX standards.
3. Implement bounded lint/type/architecture checks using existing toolchain where possible.
4. Add exception/suppression governance and fix only violations introduced or explicitly scoped.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Compliant code passes predictable local/CI standards and respects module boundaries.

## 22. Alternative flow

Legacy violation is baselined with bounded exemption/owner rather than broad rewrite.

## 23. Exception flow

Rule conflict, false positive or unsupported tooling blocks rollout and requires ADR.

## 24. Business rules

- No broad reformat/refactor; new controls cannot silently rewrite user code.
- Suppression needs reason/owner/expiry and cannot waive security/integrity.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Rules are deterministic, documented and locally reproducible.
- Boundary/import/protected-pattern checks cite architecture evidence.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Standards require authorization at server/DB boundaries and safe sensitive logging.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic compliant/non-compliant code fixtures and legacy exemption cases. Use synthetic/redacted data only.

## 28. Tests to create/update

- Lint/type/architecture rule positive/negative fixtures and suppression-expiry tests.
- CI/local parity and representative repository regression.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing build/tests/generated code conventions and preserved brownfield modules.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-89.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Standards and automated enforcement are usable with no uncontrolled churn.
- Critical unsafe patterns/boundary violations are blocked and documented.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
