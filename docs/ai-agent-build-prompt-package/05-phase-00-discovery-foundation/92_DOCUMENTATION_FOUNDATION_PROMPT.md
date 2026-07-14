# Prompt 92 — Documentation Foundation

**Prompt ID:** `CG-S5-PH0-013`  
**Package document:** `CG-AABPP-PH0-092`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-92.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-013` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Documentation and Knowledge; Epic: Repository Knowledge System; Capability: Versioned docs architecture; Feature slice: Docs taxonomy, templates, indices and validation; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a repository-native documentation foundation that supports agents, developers, users, admins, APIs, support, operations and auditable task continuation.

## 5. Business value

Prevent context loss and make every later change traceable, restartable and operable.

## 6. Source requirement

Master Prompt §§10,17–18,21; GOV templates; repository target structure. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Approved docs/templates/index/validation scripts and documentation CI paths. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Runtime source/config/schema/data, secrets and unrelated generated artifacts. Always preserve unrelated/user-owned changes.

## 13. Database impact

Define schema registry/migration documentation ownership; no DB change.

## 14. API impact

Define API contracts/changelog/example documentation ownership and validation.

## 15. UI/UX impact

Define user/admin/accessibility/workflow documentation patterns; no UI change.

## 16. Security impact

Classify/redact docs, secrets, sensitive topology and incident content by audience.

## 17. Performance impact

Docs validation must be bounded; performance claims require dated evidence.

## 18. Audit impact

Document version/owner/source/checkpoint/review/supersession and task linkage.

## 19. Data migration impact

Migration/backfill/runbook templates include recovery/rehearsal evidence.

## 20. Detailed implementation tasks

1. Inventory existing docs, duplicates, stale/conflicting content and audience ownership.
2. Implement docs taxonomy/index/templates for context/status/task/build/change/decision/error/issues/handoff/ADR/schema/API/data-flow/module/user/admin/support/runbook/release.
3. Add documentation validation for links/IDs/required sections/versions and audience-sensitive content.
4. Migrate/index current authoritative docs incrementally and document update triggers/ownership.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Fresh agent/operator finds authoritative current information and continues from checkpoint.

## 22. Alternative flow

External/source-generated doc is linked with ownership/version rather than duplicated.

## 23. Exception flow

Contradiction/stale/missing evidence is marked and blocks dependent claim.

## 24. Business rules

- No “same as above,” chat-only context or unverified production-ready claim.
- One authoritative location per fact with explicit derived views.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Indices/links/IDs/required sections/audiences/checkpoints reconcile.
- Templates are usable and update responsibilities explicit.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Audience classification controls sensitive security/finance/HR/incident content.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic/redacted examples only. Use synthetic/redacted data only.

## 28. Tests to create/update

- Link/ID/schema/required-section/status/version and stale-reference validation.
- Fresh-agent reconstruction and forbidden-sensitive-content review.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing authoritative docs, generated API docs and contributor workflows.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-92.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Documentation system is complete, navigable, validated and owned.
- Persistent task/resume evidence can be reconstructed without chat.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
