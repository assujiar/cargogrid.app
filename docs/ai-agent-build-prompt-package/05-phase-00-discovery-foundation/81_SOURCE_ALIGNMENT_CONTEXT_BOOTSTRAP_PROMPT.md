# Prompt 81 — Source Alignment and Context Bootstrap

**Prompt ID:** `CG-S5-PH0-002`  
**Package document:** `CG-AABPP-PH0-081`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-81.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-002` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Governance and Source Control; Epic: Authoritative Product Baseline; Capability: Repository-native source alignment; Feature slice: Bootstrap authoritative context and registers; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Materialize the approved CargoGrid source hierarchy, CPD/RPD decisions and package/runtime status into repository-native context without changing product policy.

## 5. Business value

Ensure every future agent uses one durable authoritative baseline rather than chat memory or conflicting documents.

## 6. Source requirement

Step 0 controls; CPD-001..023; RPD-001..040; GOV-010..019; verified Step 2–3 closures. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Repository governance/context/status/ledger/build-log documentation paths only. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Application/test/config/migration/lockfile/generated code, secrets, database and external systems. Always preserve unrelated/user-owned changes.

## 13. Database impact

No schema/data change. Record verified database identity/version only.

## 14. API impact

No contract change; index existing API documentation/evidence only.

## 15. UI/UX impact

No UI change; record portal/surface inventory and planned status accurately.

## 16. Security impact

Redact secrets/sensitive paths and preserve access/accepted-risk disclosures.

## 17. Performance impact

No runtime change; record applicable budgets and current baseline references.

## 18. Audit impact

Create traceable source/decision/context provenance and change entry.

## 19. Data migration impact

Not applicable; do not touch migrations or data.

## 20. Detailed implementation tasks

1. Create/update `CARGOGRID_CONTEXT.md` from verified sources and active repository checkpoint.
2. Install/reference decision, assumption, conflict, risk and source hierarchy registers without duplicating contradictory truth.
3. Record package-complete versus runtime-verified states, protected decisions, current strategy and preserved brownfield assets.
4. Validate references, versions, IDs and cross-document consistency.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

A fresh agent reconstructs product, repository, environment, architecture, checkpoint and risks from repository docs.

## 22. Alternative flow

External source remains linked/indexed when copying would create stale duplicate authority.

## 23. Exception flow

Missing/conflicting/stale evidence becomes an explicit blocker with owner and resume step.

## 24. Business rules

- Primary brief and ratified decisions outrank derived documents.
- No protected decision is edited or reopened silently.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- All IDs/versions/checkpoints reconcile and no unresolved variable remains.
- No implementation status is overstated.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Classify documents by audience; redact credentials, PII and sensitive operations.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

No business data; use only redacted identifiers/examples. Use synthetic/redacted data only.

## 28. Tests to create/update

- Document link/ID/version/status consistency and fresh-context reconstruction test.
- Forbidden runtime-change worktree audit.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Existing governance, source links, decision history and user-owned documentation.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-81.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Repository-native context is complete and independently reconstructable.
- Zero source conflict is hidden and no runtime file outside allowed docs changes.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
