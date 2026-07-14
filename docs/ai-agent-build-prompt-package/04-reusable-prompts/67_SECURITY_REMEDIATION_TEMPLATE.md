# Template 67 — Security Remediation

**Prompt ID:** `CG-S4-REUSE-015`  
**Package document:** `CG-AABPP-REUSE-067`  
**Version:** `0.5.0`  
**Intended use:** Correct one verified vulnerability or security-control gap.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Security and Tenant Isolation.

## 4. Objective

Remediate {{SECURITY_FINDING_ID}} at root cause, contain exposure and prove negative abuse cases.

## 5. Business value

Reduce exploitable tenant/data/system risk without breaking legitimate workflows or destroying evidence.

## 6. Source requirement

{{FINDING_EVIDENCE}}, {{SECURITY_CONTROL_IDS}}, {{INCIDENT_OR_WBS_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`, approved ADRs/migrations/contracts, verified runtime gates and baseline evidence. All must be satisfied or explicitly blocking.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; normally 5–15 files, one module boundary and at most 1–3 approved migrations. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, lockfiles unless dependency scope is explicit, secrets, generated artifacts unless authorized, tenant data, and broad refactors.

## 13. Database impact

Apply least-privilege grants/RLS/constraints through safe migration; preserve forensic evidence and tenant data.

## 14. API impact

Fix authentication/authorization/input/output/rate/SSRF/IDOR/injection contract paths with stable safe errors.

## 15. UI/UX impact

Remove exposure, unsafe rendering/redirect/file behavior and provide valid denied/session/re-auth states.

## 16. Security impact

Primary scope: threat path, assets, actors, exploit preconditions, containment, root cause, rotation/revocation and negative tests.

## 17. Performance impact

Security controls must remain bounded; rate limits/crypto/scanning/policy checks require measured budgets.

## 18. Audit impact

Preserve evidence and log detection/privileged response/remediation without secrets or attacker payload leakage.

## 19. Data migration impact

Compromised/unsafe data repair requires a separate evidence-preserving, idempotent plan and legal/incident authority.

## 20. Detailed implementation tasks

1. Validate finding safely without active exploitation of production or cross-tenant data.
2. Assess exposure window/blast radius; contain with recorded authority and preserve evidence.
3. Implement least-scope root-cause remediation plus key/token/session rotation or data action if authorized.
4. Add negative tests, detection/alert, regression, incident/runbook and disclosure/communication records.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Legitimate authorized flow succeeds through the remediated control.

## 22. Alternative flow

Supported service/support/integration path remains least privilege and audited.

## 23. Exception flow

Exploit, bypass, malformed input, stale credential, replay and unauthorized access fail closed and alert appropriately.

## 24. Business rules

- Never weaken another control or conceal a critical failure to restore service.
- Supreme Admin ratified authority is disclosed rather than falsely described as tamper-proof.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Finding is reproducible safely before and blocked after; residual exposure is classified.
- Rotation/revocation/session/cache propagation completes within documented bounds.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Test anonymous, authenticated wrong tenant, wrong role/scope, field/record IDOR, service/support and privileged paths.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Synthetic exploit fixtures, two tenants, roles/scopes, malicious inputs/files/URLs, expired/revoked credentials and safe control cases. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Specific negative exploit/bypass tests plus legitimate-flow regression.
- RLS/RBAC/API/file/session/rate/audit/detection tests and dependency scan as relevant.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Authentication, tenant access, integrations, files, jobs, performance and critical business flows.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Exploit path is blocked at root cause with negative evidence and legitimate flow preserved.
- Containment, rotation, detection, documentation and residual-risk approval are complete.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
