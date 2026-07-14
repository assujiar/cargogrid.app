# Prompt 86 — Environment Validation Foundation

**Prompt ID:** `CG-S5-PH0-007`  
**Package document:** `CG-AABPP-PH0-086`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-86.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-007` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Developer Experience and DevOps; Epic: Environment Safety; Capability: Typed environment validation; Feature slice: Fail-fast configuration contract; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement fail-fast validation for environment variables, service endpoints and environment class across local/test/CI/staging/UAT/production.

## 5. Business value

Prevent misconfiguration, secret misuse and accidental connection to the wrong tenant/data environment.

## 6. Source requirement

DevOps workstream; security baseline; environment inventory; PH0-085. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Central environment-schema, startup validation, tests, examples and documentation paths. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Real env files/secrets, unrelated config, services/data and deployment mutations. Always preserve unrelated/user-owned changes.

## 13. Database impact

Validate DB URL/class/role expectations without printing credentials; block unsafe production linkage in local/test.

## 14. API impact

Validate public/server endpoint separation, origins and provider settings.

## 15. UI/UX impact

Expose only approved public variables; never serialize server secrets.

## 16. Security impact

Classify secret/public values, required-by-environment rules, rotation metadata and redacted errors.

## 17. Performance impact

Validation runs at startup/build with negligible measured overhead.

## 18. Audit impact

Log validation outcome/environment class/version without values.

## 19. Data migration impact

No migration/data change.

## 20. Detailed implementation tasks

1. Inventory variables and classify public/server/secret/environment-specific/optional/deprecated.
2. Implement typed schema and redacted fail-fast validation at approved startup/build boundaries.
3. Add cross-variable rules for environment class, URLs, auth/storage/integration keys and production safeguards.
4. Update examples, CI checks, tests and operator troubleshooting.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Valid configuration starts/builds with a recorded redacted validation result.

## 22. Alternative flow

Optional feature configuration is absent and feature remains explicitly disabled.

## 23. Exception flow

Missing/malformed/leaked/mis-scoped/production-linked value fails before unsafe operation.

## 24. Business rules

- No default secret or permissive fallback; client exposure is allowlisted.
- Errors name variable/control without outputting value.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Every consumed variable is defined/classified and every declared variable has a consumer or deprecation plan.
- Server/client bundles contain no secret values.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Secret access is least privilege and environment-bound.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic valid/invalid env maps, production-like endpoints without credentials and client bundle fixtures. Use synthetic/redacted data only.

## 28. Tests to create/update

- Schema/cross-field/environment-class validation and redaction tests.
- Secret-in-client, missing required, malformed URL, production-link and deprecated variable negatives.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Local bootstrap, CI/build, auth/storage/integration startup and deployment docs.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-86.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- All environments fail fast safely on invalid configuration with no secret disclosure.
- Existing valid setup and CI/build remain functional.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
