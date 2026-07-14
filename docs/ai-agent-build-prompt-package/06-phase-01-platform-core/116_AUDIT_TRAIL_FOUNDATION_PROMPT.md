# Prompt 116 — Audit Trail Foundation

**Prompt ID:** `CG-S6-PLT-013`  
**Package document:** `CG-AABPP-PLT-116`  
**Version:** `0.7.0`  
**Runtime build log:** `docs/build-log/phase-01/PLT-116.md`

Do not begin until Prompt 104 marks this task `READY`, all variables are resolved, and `PHASE_0_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S6-PLT-013` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 1 — Platform Core`; package `0.7.0`.

## 3. Workstream

Workstream: Audit and Compliance; Epic: System Accountability; Capability: Canonical audit event foundation; Feature slice: Append-oriented tenant-aware audit capture/query/export; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement canonical audit events and capture primitives for privileged, access, configuration and platform changes with explicit Supreme Admin limitations.

## 5. Business value

Provide accountable evidence and troubleshooting across all later modules without overstating tamper resistance.

## 6. Source requirement

Audit requirements; data classification/retention; RPD-022/025; WBS task. Cite exact runtime evidence, ADR and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 1 index/WBS, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, plan, expected files/migrations and stop on tenant/data/finance/security conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`; every prerequisite from the execution index must be `VERIFIED`.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS}}`; identify schemas, services, REST/GraphQL, jobs/files, portals, tests/docs and phase gates.

## 11. Allowed files/folders

Audit schema/migrations/service/instrumentation/query/tests/docs and bounded adapters. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Claiming immutable/tamper-proof, sensitive payload dumping, domain-wide instrumentation outside scope. Preserve unrelated/user-owned changes, applied migrations and protected decisions.

## 13. Database impact

Add tenant-aware audit event schema, actor/context/action/resource/result/reason/correlation/before-after refs, indexes, retention/legal hold and RLS.

## 14. API impact

Shared server capture/query/export contracts with field/record permissions and pagination.

## 15. UI/UX impact

Reusable timeline/query view models only; portal pages later.

## 16. Security impact

No secret/unsafe PII payload; privileged access controls, redaction and event integrity checks.

## 17. Performance impact

Asynchronous/non-blocking where safe, bounded payload, tenant/time/resource indexes and server pagination.

## 18. Audit impact

Primary scope; audit itself records capture failures/config/privileged access while acknowledging Supreme CRUD.

## 19. Data migration impact

Migrate existing audit sources by reference/controlled mapping; no fabricated history.

## 20. Detailed implementation tasks

1. Define event taxonomy/schema, required context, sensitivity/redaction and retention.
2. Implement transaction-safe capture/outbox/failure handling and shared instrumentation API.
3. Implement permission-aware query/export with pagination and legal-hold semantics.
4. Integrate representative platform events and add completeness/redaction/privileged-risk tests/docs.
5. Compare baseline/post-change evidence and update persistent records.

## 21. Main flow

Platform action emits one correlated tenant-aware audit event queryable by authorized actor.

## 22. Alternative flow

Failed/async action records outcome without duplicating business transaction.

## 23. Exception flow

Audit sink failure follows documented fail-closed/fail-open policy by criticality and alerts.

## 24. Business rules

- Normal roles cannot edit audit records; Supreme absolute CRUD means no tamper-proof claim.
- Audit is distinct from diagnostic logs and business ledgers.
- One shared multi-tenant codebase; preserve CPD/RPD and canonical semantics.

## 25. Validation rules

- Required fields/context/result/reason and redaction deterministic.
- Duplicate/missing/cross-tenant event access is detected.
- Validate server and database boundaries; no unresolved placeholder or client-only rule.

## 26. Access rules

- Query/export limited by tenant/role/scope/field/record; privileged access itself audited.
- Enforce entitlement, four-layer context, RBAC/scope, RLS, field/record rules and server-only secrets as applicable.

## 27. Test data requirement

Two tenants, platform actions, sensitive fields, failures, support/impersonation and Supreme edits. Use synthetic/redacted data with at least two tenants for tenant-scoped behavior.

## 28. Tests to create/update

- Capture/idempotency/correlation/redaction/retention/query/export tests.
- RLS/RBAC/cross-tenant/field access, failure handling and RPD-022 disclosure tests.
- Cover main/alternative/exception, audit and negative abuse paths.

## 29. Regression tests

- Transactions, observability, performance and current logs/audit artifacts.
- Separate pre-existing failures; never weaken tests/RLS/RBAC/validation.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install/shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-01/PLT-116.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and phase handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Representative platform actions produce complete safe audit evidence.
- Access/retention/failure/performance pass and claims disclose Supreme risk.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`{{NEXT_PROMPT_ID_FROM_PLATFORM_INDEX}}` only after acceptance/dependencies pass; otherwise output exact blocked/failed/partial resume prompt.

