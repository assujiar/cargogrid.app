# Prompt 93 — Observability Baseline

**Prompt ID:** `CG-S5-PH0-014`  
**Package document:** `CG-AABPP-PH0-093`  
**Version:** `0.6.0`  
**Runtime build log:** `docs/build-log/phase-00/PH0-93.md`

Do not begin until Prompt 80 marks this task `READY`, all variables are resolved and the repository checkpoint matches verified discovery/architecture evidence.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S5-PH0-014` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 0 — Discovery and Foundation`; package `0.6.0`.

## 3. Workstream

Workstream: DevOps and Observability; Epic: Operational Evidence; Capability: Logs, metrics, traces and alerts foundation; Feature slice: Tenant-safe correlation and foundation health telemetry; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement the minimum observability foundation for app, database, jobs, integrations, security and audit signals without exposing sensitive tenant data.

## 5. Business value

Enable detection, diagnosis and evidence-based operation before domain complexity grows.

## 6. Source requirement

Technical Architecture observability; DevOps workstream; security/data classification; Delivery Plan. Cite exact runtime evidence and approved ADRs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, strategy, current implementation, package manager/scripts, framework/database/tool versions, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 0 index/WBS, relevant build logs and source requirements. Inspect current files/contracts and package scripts. Capture baseline, short implementation plan and expected files. Stop on unresolved tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; match the Phase 0 execution index and prove each is `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify consumers, contracts, environment/CI/tests/docs and Phase 1 gates.

## 11. Allowed files/folders

Approved observability middleware/config/tests/docs/runbook and bounded health endpoints. Resolve to exact paths before editing; normally 5–15 files.

## 12. Forbidden files/folders

Production alert/service mutation, domain dashboards, secret values, unrelated business code. Always preserve unrelated/user-owned changes.

## 13. Database impact

Add no speculative telemetry schema; approved audit/operational tables require migration and retention/RLS controls.

## 14. API impact

Define correlation/request IDs, safe error/latency metrics and health/readiness boundaries.

## 15. UI/UX impact

Provide no business dashboard; operator health views only if explicitly within approved scope.

## 16. Security impact

Redact secrets/PII/payroll/tax/bank, prevent tenant label cardinality leaks and restrict logs/telemetry.

## 17. Performance impact

Bound instrumentation overhead/cardinality/sampling/export failure behavior.

## 18. Audit impact

Separate security/business audit from diagnostic logs; preserve correlation and privileged access.

## 19. Data migration impact

No data migration; telemetry retention transition requires separate task.

## 20. Detailed implementation tasks

1. Inventory current logs/metrics/traces/health/error handling and preserve working instrumentation.
2. Define event/field/correlation/redaction/severity/cardinality/retention/ownership standards.
3. Implement foundation middleware/hooks for safe request/job/integration/db/error health signals.
4. Add local/test evidence, alert/runbook stubs and telemetry failure/degraded behavior.
5. Compare baseline/post-change evidence and update all persistent records.

## 21. Main flow

A foundation request/job failure is traceable across components without sensitive leakage.

## 22. Alternative flow

Telemetry backend unavailable and application degrades safely without losing critical audit.

## 23. Exception flow

High cardinality, secret/PII leak, exporter storm or misleading health blocks rollout.

## 24. Business rules

- Logs are not audit substitutes; audit has stronger retention/access semantics.
- Tenant identifiers use safe pseudonymous/bounded dimensions.
- Preserve CPD/RPD decisions and package-versus-runtime state distinctions.

## 25. Validation rules

- Required correlation propagates and redaction/cardinality/health semantics are deterministic.
- Instrumentation failure cannot fail core transaction unexpectedly.
- Validate trusted server/tooling boundaries; no unresolved placeholder may pass.

## 26. Access rules

- Telemetry/audit access is least privilege, environment/tenant sensitive and recorded.
- Least privilege, strict tenant isolation and server-only secrets remain mandatory.

## 27. Test data requirement

Synthetic requests/jobs/errors with secret/PII markers, multiple tenants and exporter outage. Use synthetic/redacted data only.

## 28. Tests to create/update

- Correlation, structured fields, redaction, severity, health/readiness and exporter-failure tests.
- Cardinality/overhead baseline and privileged access/audit tests.
- Include negative/failure and evidence-readback cases.

## 29. Regression tests

- Request/job behavior, performance, existing logs and error handling.
- Separate pre-existing failures; never disable/weaken tests or controls.

## 30. Commands to run

Use detected repository scripts/package manager. Run scoped validation then applicable lint, typecheck, unit/integration/security/migration/E2E/accessibility/performance and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not auto-install or run unsafe defaults.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-00/PH0-93.md`, change manifest, regression/traceability matrices, relevant ADR/schema/API/data-flow/module/error/issues/user/admin/support docs, and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact file/config/schema/data/environment rollback or forward-fix. On partial/unsafe result, stop, update error/issues/handoff and generate a bounded resume prompt; never restart the phase blindly.

## 33. Acceptance criteria

- Core foundation signals are traceable, safe and documented with bounded overhead.
- No sensitive leak, false health or unsupported monitoring claim.
- Mandatory gates pass, worktree is reconciled and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation/evidence, regression, security/performance checks, documentation, task/change records, checkpoint and handoff agree. Phase 0 and production readiness are not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/config/migrations/contracts; DB/API/UI/security/performance/audit/data effects; tests/commands/results; docs; errors/recovery; risks/issues; rollback; commit/branch; and next eligible prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PHASE0_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt and stop.
