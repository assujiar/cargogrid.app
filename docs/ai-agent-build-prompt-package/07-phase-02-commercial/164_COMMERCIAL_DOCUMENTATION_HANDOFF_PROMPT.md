# Prompt 164 — Commercial Documentation and Handoff

**Prompt ID:** `CG-S7-COM-023`  
**Package document:** `CG-AABPP-COM-164`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-164.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-023` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Commercial Completion; Epic: Knowledge and Handoff; Capability: Commercial documentation reconciliation; Feature slice: Verified implementation/evidence→durable docs→Phase 3 handoff; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Reconcile Commercial architecture, schema, contracts, workflows, access, calculations, runbooks, evidence and residual risks into a context-independent handoff.

## 5. Business value

Let a new agent or Phase 3 team continue from one trusted checkpoint without conversation history or rediscovery.

## 6. Source requirement

COM-143..163; governance/context/status/ledger/change/error/issues/handoff contracts. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-163 VERIFIED; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-165; Step 8; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Commercial Completion schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

No feature schema by default; document authoritative entities, constraints, migrations, RLS, money/version/lineage and recovery behavior.

## 14. API impact

Document REST/GraphQL/shared-service contracts, errors, idempotency, jobs/webhooks, file handling and Job Order input compatibility.

## 15. UI/UX impact

Document routes/workflows, roles, complete states, responsive/accessibility behavior and customer acceptance surfaces.

## 16. Security impact

Document tenant/organizational/field/record scopes, sensitive commercial fields, customer tokens, support access and RPD-022 exception. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Document baselines/budgets, indexed queries, dashboard/report controls, cache/timeout limits and scale thresholds.

## 18. Audit impact

Reconcile audit events, evidence locations, privileged access, acceptance/conversion/override trails and known limitations.

## 19. Data migration impact

Document install/rebuild/upgrade/rollback/forward-fix, legacy reconciliation, fixtures/seeds and last trusted schema checkpoint.

## 20. Detailed implementation tasks

1. Reconcile context/status/WBS/task/change/decision/error/issues and traceability against actual checkpoint.
2. Update architecture/schema/data-flow/API/UI/access/money/lineage/report/runbook documents.
3. Create Phase 3 Job Order handoff contract examples, compatibility notes and unresolved dependency list.
4. Index tests/commands/evidence and disclose residual risks/accepted decisions.
5. Produce context-independent handoff and mark COM-165 eligible only after readback consistency.

## 21. Main flow

All durable documents match verified code/schema/contracts/evidence and identify one exact checkpoint plus next closure task.

## 22. Alternative flow

A bounded residual documentation gap is assigned with impact and phase stays partial until resolved.

## 23. Exception flow

Contradictory schema/API/state/evidence, missing rollback, unknown issue or stale handoff blocks closure.

## 24. Business rules

- Documentation describes verified reality, not intended behavior.
- No secret, customer PII or unsafe credential/example enters documentation.
- Package state, runtime state and production/GA state remain distinct.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Every source requirement/capability/task links to implementation and evidence or explicit gap.
- Files/routes/migrations/commands/states in docs match repository readback.
- Step 8 receives exact JobOrderDraftInput version, lineage, fixtures and eligibility gate.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Store documents/evidence under repository policy; redact secrets/PII and restrict sensitive security evidence appropriately. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Use synthetic/redacted examples for full happy/exception flows, money, acceptance, conversion and Job Order handoff. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Documentation link/schema/contract/example/readback validation.
- Handoff reconstruction by a context-free reviewer or scripted checklist.
- Final smoke/regression/evidence-index integrity checks.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

All governance/control docs, build logs, API/schema/user/admin/support docs and Step 8 inputs. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-164.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Durable docs reconstruct the verified Commercial checkpoint without chat context.
- All evidence, residual risks and recovery paths are findable and consistent.
- Closure and Phase 3 handoff inputs are exact and ready.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-024` / `COM-165` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

