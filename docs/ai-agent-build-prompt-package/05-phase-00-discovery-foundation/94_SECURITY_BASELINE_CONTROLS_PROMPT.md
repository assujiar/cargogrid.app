# Prompt 94 — Security Baseline Controls

**Prompt ID:** `CG-S5-PH0-015`  
**Package document:** `CG-AABPP-PH0-094`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-94.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-015` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: Security Engineering; Epic: Secure-by-Default Foundation; Capability: Application security controls baseline; Feature slice: Foundational headers/input/secrets/session/dependency/file safeguards; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement prioritized Phase 0 security baseline controls supported by verified findings and threat evidence without pretending later domain RLS/RBAC is complete.

## 5. Business value

Remove foundational exposure and make later modules inherit safe defaults.

## 6. Source requirement

Security baseline audit; Master Prompt §12; Security workstream; accepted risks. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Approved security foundation config/middleware/tests/docs/scanner rules and bounded dependency metadata when explicitly authorized. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Unrelated feature/auth redesign, real exploit against production, real secrets/data, broad dependency upgrade. Always preserve unrelated/user-owned changes.

## 13. Database impact

Preserve/prepare least-privilege/RLS posture; schema policy changes use dedicated authorized templates.

## 14. API impact

Foundation input/error/rate/CORS/CSRF/security header/auth/session patterns where architecture applies.

## 15. UI/UX impact

Safe rendering/redirect/error/session states; no client secrets or authorization-only UI.

## 16. Security impact

Primary scope: secret scanning, secure defaults, dependencies, headers, validation, session/token, upload primitives and incident/key rotation readiness.

## 17. Performance impact

Measure security middleware/scanning overhead and rate-limit behavior.

## 18. Audit impact

Security events and privileged baseline changes are logged/redacted; RPD-022 disclosed.

## 19. Data migration impact

No broad data repair; compromised data/keys use incident/data-migration authority.

## 20. Detailed implementation tasks

1. Prioritize verified baseline findings and Phase 0 controls; separate later tenant/domain tasks.
2. Implement approved secure defaults/checks within one bounded foundation slice and existing architecture.
3. Add negative tests for bypass/injection/IDOR/CSRF/XSS/SSRF/redirect/file/secret/session controls as applicable.
4. Document threat/control mapping, rotation/incident steps, residual risks and later owners.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

Legitimate foundation flow succeeds through safe defaults.

## 22. Alternative flow

Optional integration/file/auth capability disabled securely when not configured.

## 23. Exception flow

Malicious/malformed/unauthorized/stale credential path fails closed and produces safe evidence.

## 24. Business rules

- No security bypass for convenience and no service role in client.
- No release with critical tenant/security defect; Supreme Admin risk is disclosed.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Every implemented control maps to threat/finding and negative evidence.
- Residual/later controls are explicit, not falsely complete.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Least privilege, server-only secrets, time/purpose-bound support and privileged audit.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic malicious inputs/files/URLs/tokens, two tenants where applicable and revoked/expired credentials. Use synthetic/redacted data only.

## 28. Tests to create/update

- Specific control negative tests, secret scan/dependency audit and legitimate-flow regression.
- Session/token/rate/header/upload/redaction tests as applicable.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Auth, API, local/CI setup, observability, files and performance.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-94.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Prioritized Phase 0 controls pass negative evidence with legitimate paths preserved.
- Residual critical blocker is zero or Phase 0 remains blocked.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
