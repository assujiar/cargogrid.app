# Prompt 85 — Development Environment Foundation

**Prompt ID:** `CG-S5-PH0-006`  
**Package document:** `CG-AABPP-PH0-085`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-85.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-006` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Developer Experience; Epic: Reproducible Local Development; Capability: Developer environment bootstrap; Feature slice: One-command documented safe local setup; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a reproducible local development setup aligned with the verified repository toolchain and isolated from production data/services.

## 5. Business value

Reduce setup drift and enable reliable build/test work without secret leakage or accidental production impact.

## 6. Source requirement

Verified toolchain/dependency/database baseline; repository target structure; DevOps workstream. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Verified dev-environment scripts/config/examples/docs and bounded package metadata explicitly approved. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Production/staging config, real secrets/data, applied migration edits, unrelated dependency upgrades. Always preserve unrelated/user-owned changes.

## 13. Database impact

Use local/disposable database only; document reset/seed/migration behavior and production-link safeguards.

## 14. API impact

Start only local/test API dependencies through documented scripts.

## 15. UI/UX impact

Provide local app/portal start instructions and environment validation feedback.

## 16. Security impact

Use example variable names, secret manager guidance and production-deny checks; never commit values.

## 17. Performance impact

Keep bootstrap bounded/cache-aware; record typical setup/build times as evidence, not SLA.

## 18. Audit impact

Record tool versions, commands, generated artifacts and environment changes.

## 19. Data migration impact

Apply existing migrations only to disposable local DB; clean rebuild/upgrade verification belongs to tests.

## 20. Detailed implementation tasks

1. Detect and pin supported runtime/package/database/tool versions from repository evidence.
2. Create/update safe example environment schema, bootstrap scripts/config and dependency/service instructions.
3. Add production-link/secret/preflight safeguards and deterministic local database/seed flow.
4. Validate clean checkout setup in an isolated environment and document troubleshooting/recovery.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Authorized developer creates a working isolated local environment from clean checkout.

## 22. Alternative flow

Supported container/native path produces equivalent versions and gates if architecture permits.

## 23. Exception flow

Missing tool/secret, version mismatch, port conflict, production link or failed seed stops safely with actionable error.

## 24. Business rules

- Repository’s verified package manager/lockfile is authoritative.
- No real tenant data, production credentials or silent global dependency assumptions.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Tool/env schema versions and required variables are validated before services start.
- Clean bootstrap leaves only documented generated/cache changes.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Local credentials use least privilege and synthetic tenants; service role stays server-only.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Deterministic synthetic seed with at least two tenants/roles and no sensitive real data. Use synthetic/redacted data only.

## 28. Tests to create/update

- Clean-checkout bootstrap, version/env validation, local DB reset/seed/migration and smoke tests.
- Secret scan and production-link negative test.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing developer scripts, package lock, CI parity and user-owned environment files.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-85.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Clean isolated setup is reproducible from docs/scripts with passing smoke/baseline.
- No secret, real data or production dependency is introduced.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
