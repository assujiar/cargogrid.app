# Prompt 96 — Initial Threat Model

**Prompt ID:** `CG-S5-PH0-017`  
**Package document:** `CG-AABPP-PH0-096`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-96.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-017` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Security Architecture; Epic: Threat and Abuse Analysis; Capability: Initial system threat model; Feature slice: Architecture and Phase 0 attack-path model; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Create and validate the initial CargoGrid threat model tied to actual architecture, trust boundaries, data classes and planned controls.

## 5. Business value

Prioritize security work by credible attack paths before Platform Core and domain implementation.

## 6. Source requirement

Verified security baseline; domain/data/dependency maps; data classification; Master Prompt §12. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Threat-model docs/diagrams/registers/validation and related traceability/build-log. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Active exploitation, runtime source/config/data change, secret disclosure. Always preserve unrelated/user-owned changes.

## 13. Database impact

Model database/RLS/service-role/migration/backup threats; no DB change.

## 14. API impact

Model REST/GraphQL/webhook/job/integration auth, injection, replay, rate and contract abuse.

## 15. UI/UX impact

Model XSS/CSRF/open redirect/session/impersonation/file/portal and client-secret threats.

## 16. Security impact

Primary scope: assets, actors, trust boundaries, STRIDE/abuse cases, likelihood/impact, existing/planned controls and residual risk.

## 17. Performance impact

Include resource exhaustion, query abuse, job storms, file/report amplification and detection thresholds.

## 18. Audit impact

Threat/control/risk/owner/decision history and accepted-risk authority are traceable.

## 19. Data migration impact

Model migration/backfill/restore/cutover integrity threats; no data change.

## 20. Detailed implementation tasks

1. Define scope/checkpoint/assets/data classes/actors/trust boundaries and diagrams/tables from runtime evidence.
2. Enumerate threats/abuse cases for tenants, access, admin/support, APIs, jobs, files, integrations, finance/data and operations.
3. Map current/planned preventive/detective/recovery controls, test evidence, owners and phase/WBS tasks.
4. Rank residual risks, critical blockers, assumptions, monitoring and update triggers.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Credible threat maps to owned control/test/task and residual risk state.

## 22. Alternative flow

Accepted product risk is explicitly documented with compensating control/claim limitation.

## 23. Exception flow

Critical unowned path or contradictory architecture blocks Phase 0/affected Phase 1 entry.

## 24. Business rules

- Do not actively exploit production/cross-tenant systems to validate the model.
- RPD-022, direct GA and recovery contract limitations affect risk.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Every trust boundary/data class and critical interface has threat coverage.
- Risk ranking is reproducible and no control is credited without evidence/plan.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Threat-model detail is audience-controlled; actionable secrets/exploit detail are redacted.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic abuse scenarios and redacted architecture evidence only. Use synthetic/redacted data only.

## 28. Tests to create/update

- Threat/control/owner/requirement linkage, orphan/duplicate and risk-ranking validation.
- Table/diagram consistency and critical blocker checks.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Security baseline, data-flow/domain/dependency maps, classification and WBS.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-96.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Initial threat model is complete, evidence-backed and task-linked.
- All critical threats have controls/owners or Phase 0 remains blocked.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
