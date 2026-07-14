# Prompt 101 — Phase 0 Documentation and Handoff

**Prompt ID:** `CG-S5-PH0-022`  
**Package document:** `CG-AABPP-PH0-101`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-101.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-022` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Documentation and Phase Operations; Epic: Phase Completion Evidence; Capability: Authoritative Phase 0 handoff; Feature slice: Reconcile docs, evidence and Phase 1 entry package; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Reconcile all Phase 0 repository documentation, evidence, checkpoint and next-task instructions for an independent Phase 1 agent.

## 5. Business value

Make Phase 0 restartable/auditable and prevent Platform Core work from relying on hidden context.

## 6. Source requirement

PH0-080..100 outputs; documentation foundation; Master Prompt §§17–18/21. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Phase 0 docs/indices/ledgers/build logs/validation and handoff paths. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Runtime source/config/schema/data/deployment and unrelated phase docs. Always preserve unrelated/user-owned changes.

## 13. Database impact

Document actual schema/migration/seed/checkpoint only; no DB change.

## 14. API impact

Document actual foundation contracts only; no API change.

## 15. UI/UX impact

Document design foundation and supported evidence only; no UI change.

## 16. Security impact

Redact secrets/sensitive incident/threat content by audience; retain accepted-risk disclosures.

## 17. Performance impact

Document measured baselines/limits/environment; no unsupported SLA.

## 18. Audit impact

Final Phase 0 index links task/change/decision/error/issues/artifacts/approvals/checkpoint.

## 19. Data migration impact

Document migration history/rebuild/upgrade/recovery status; no execution.

## 20. Detailed implementation tasks

1. Read back every task/build log/change/decision/error/issues/evidence artifact at the final checkpoint.
2. Update context/status/traceability/regression/schema/API/data-flow/module/docs/runbooks and Phase 0 execution index.
3. Create Phase 1 entry package: verified dependencies, preserved assets, environment commands, known issues, risks, exact first eligible prompt.
4. Run docs/link/ID/version/status/sensitive-content/fresh-context validation and resolve contradictions.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Fresh agent reconstructs Phase 0 and starts the exact eligible Phase 1 task safely.

## 22. Alternative flow

Open non-critical issue remains linked with owner/workaround/expiry and no false closure.

## 23. Exception flow

Contradictory/missing/stale evidence or unresolved critical blocker prevents handoff and closure.

## 24. Business rules

- Documentation mirrors verified repository state; it cannot turn partial into complete.
- No chat-only assumption or “same as above.”
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- All documents share checkpoint/version/status and bidirectional links.
- No secret/PII or unsupported readiness/recovery claim.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Separate public/user/admin/API/support/internal security/incident audiences.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic/redacted documentation examples only. Use synthetic/redacted data only.

## 28. Tests to create/update

- Links/IDs/required sections/status/version/checkpoint and sensitive-content validation.
- Fresh-agent reconstruction and exact next-prompt rehearsal.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- All persistent docs, WBS/traceability, runbooks and build logs.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-101.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Documentation/handoff is complete, internally consistent and context-independent.
- Prompt 102 has all evidence required for closure.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.

