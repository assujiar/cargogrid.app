# Prompt 98 — Feature Flag Foundation

**Prompt ID:** `CG-S5-PH0-019`  
**Package document:** `CG-AABPP-PH0-098`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-98.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-019` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Platform Configuration; Epic: Safe Change Exposure; Capability: Feature flag foundation; Feature slice: Typed server-authoritative flag evaluation and audit; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the Phase 0 feature-flag foundation for environment, tenant, module, feature, cohort and effective-date targeting without bypassing security or entitlements.

## 5. Business value

Enable controlled rollout and rollback of later work while preserving one shared codebase and canonical behavior.

## 6. Source requirement

PKG-PLT-FLG-001; Technical Architecture feature flags; RPD direct-GA decisions; configuration workstream. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Approved feature-flag core/config/schema/migration/tests/docs within foundation boundary. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Domain feature flags/behavior, authorization bypass, generic tenant fork and unrelated configuration engines. Always preserve unrelated/user-owned changes.

## 13. Database impact

If persistence is approved, tenant-aware versioned flag/config tables require RLS, constraints, indexes and migration tests.

## 14. API impact

Define typed evaluation/admin contract, caching/invalidation and safe errors; server decision authoritative.

## 15. UI/UX impact

Provide no broad admin builder unless later authorized; client receives only necessary evaluated state.

## 16. Security impact

Flags cannot grant permission, weaken RLS/RBAC/validation, expose secrets or hide critical security/finance defects.

## 17. Performance impact

Bound evaluation/cache/invalidation/cardinality and prevent per-row/loop remote calls.

## 18. Audit impact

Audit flag definition/version/effective date/target/change/actor/reason/evaluation context where required.

## 19. Data migration impact

Flag bootstrap/seed/version migration is deterministic and rollback-capable.

## 20. Detailed implementation tasks

1. Define flag types, ownership, naming, lifecycle, precedence and targeting dimensions.
2. Implement typed server-authoritative evaluation, defaults, cache/invalidation and safe unavailable behavior.
3. Implement minimal controlled management/config or repository source according to approved ADR.
4. Add tests, audit/observability, kill-switch/rollback semantics and later phase adoption guide.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Authorized context evaluates deterministic flag state and product applies it without bypass.

## 22. Alternative flow

Flag/provider unavailable uses explicitly safe default and records degraded state.

## 23. Exception flow

Invalid/conflicting/expired/unauthorized target or stale cache fails safely.

## 24. Business rules

- Flags control exposure, not access, data integrity or financial truth.
- Direct GA/no external pilot remains; internal flags do not relabel production requirements.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Precedence/environment/tenant/module/cohort/effective-date semantics are deterministic.
- Unknown flag and stale configuration behavior are explicit.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Flag management is privileged/audited; evaluation context cannot cross tenants.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Two tenants, environments, modules, cohorts, dates, missing/conflicting flags and cache invalidation. Use synthetic/redacted data only.

## 28. Tests to create/update

- Evaluation/precedence/default/expiry/cohort/cache/audit tests.
- Cross-tenant management/evaluation, security bypass negative and performance tests.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Entitlements/configuration, build/runtime, SSR/client hydration, audit and critical paths.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-98.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Foundation evaluates safely/deterministically with no access bypass.
- Rollback/kill-switch, audit, performance and documentation evidence passes.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
