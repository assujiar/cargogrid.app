# Template 71 — Incident Response

**Prompt ID:** `CG-S4-REUSE-019`  
**Package document:** `CG-AABPP-REUSE-071`  
**Version:** `0.5.0`  
**Intended use:** Contain, investigate and recover one active or recent CargoGrid incident.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. Emergency/recovery templates require their recorded authority. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger/incident item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version or emergency authority: `{{PHASE_PACKAGE_OR_AUTHORITY}}`.

## 3. Workstream

Incident Response and Operations.

## 4. Objective

Respond to {{INCIDENT_ID}} by protecting people/tenants/data, preserving evidence, containing impact and restoring trusted service.

## 5. Business value

Limit harm and recover safely without destroying evidence, widening exposure or creating uncontrolled changes.

## 6. Source requirement

{{ALERT_OR_REPORT_EVIDENCE}}, {{INCIDENT_POLICY}}, {{AUTHORITY_RECORD}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase/incident build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS_OR_AUTHORITY}}`, approved ADRs/migrations/contracts, verified runtime gates or recorded recovery/emergency authority, and baseline evidence.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; one bounded objective and module/operational boundary. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, unapproved lockfile/dependency changes, secrets, tenant data and broad refactors.

## 13. Database impact

Prefer read-only evidence; writes/repairs require explicit containment/recovery authority, backups and reconciliation.

## 14. API impact

Contain affected routes/keys/webhooks with compatibility and customer-impact awareness; preserve evidence.

## 15. UI/UX impact

Communicate accurate degraded/maintenance states and prevent unsafe actions; no false success.

## 16. Security impact

Classify severity, exposure, tenant/data/credential impact, evidence chain, containment, rotation/revocation and notification obligations.

## 17. Performance impact

Stabilize overload without hiding root cause; capture saturation/latency/error evidence and safe capacity controls.

## 18. Audit impact

Preserve timeline, commands, actors, approvals, evidence hashes/references, tenant impact and communication; never delete relevant logs.

## 19. Data migration impact

No ad hoc repair; isolate affected records and use authorized idempotent recovery/reconciliation task.

## 20. Detailed implementation tasks

1. Establish incident commander/authority, severity, timeline, trusted checkpoint and communication cadence.
2. Preserve/redact evidence; assess blast radius, tenants/data/finance/security and ongoing threat.
3. Contain minimally, rotate/revoke when authorized, validate containment and monitor recurrence.
4. Diagnose root cause, choose recovery/rollback/hotfix path, reconcile data and complete post-incident actions.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Incident is detected, contained, recovered and monitored with evidence and stakeholder communication.

## 22. Alternative flow

Service remains safely degraded/read-only while data/tenant trust is evaluated.

## 23. Exception flow

Lost repository/database trust, active cross-tenant exposure, uncertain financial integrity or failed containment triggers escalation and stronger isolation.

## 24. Business rules

- Safety and evidence preservation outrank speed; do not speculate publicly or suppress failures.
- RPO/RTO claims follow contract; silence means best effort without guarantee.
- Preserve canonical entities/statuses, ratified decisions and explicit authority boundaries.

## 25. Validation rules

- Severity/impact/containment/recovery are evidence-backed and independently checked.
- Recovery returns to a trusted checkpoint with reconciled data/security state.
- Validate on trusted server/database/operational boundaries; never rely on client-only checks.

## 26. Access rules

- Emergency access is least privilege, time/purpose-bound, approved and fully audited.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Use redacted/synthetic reproduction only; never copy exposed tenant/credential data into source or unsafe channels. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Containment verification, exploit/recurrence negative, health/smoke and affected critical-flow tests.
- Data/finance reconciliation, credential revocation/session invalidation and monitoring alert tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Unaffected tenants/modules, auth, integrations, jobs, files and operational controls.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository/runbook commands. Run scoped checks, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility/build/health gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm, auto-install tooling or run destructive commands without authority.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, build/incident log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/handoff/user/admin/API/support/release/runbook docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag, contract and operational rollback/forward-fix; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Impact is contained, trusted service restored or safely degraded, and evidence/communications are complete.
- Root cause/recovery/residual risk/next remediation and post-incident review are owned.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Authorized work, positive/negative/regression evidence, security/performance/audit checks, documentation, change/task/error records, checkpoint and handoff are reconciled. Status is `VERIFIED` or the precise blocked/recovery state; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/incident/checkpoint/status; objective/source/authority; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; artifact/commit/branch/environment; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
