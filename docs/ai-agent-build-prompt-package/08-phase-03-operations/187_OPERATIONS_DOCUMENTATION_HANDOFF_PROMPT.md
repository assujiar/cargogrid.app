# Prompt 187 — Operations Documentation and Handoff

**Prompt ID:** `CG-S8-OPS-021`  
**Package document:** `CG-AABPP-OPS-187`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-187.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-021` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Operations Completion; Epic: Knowledge and Handoff; Capability: Operations documentation reconciliation; Feature slice: Verified implementation/evidence→durable docs→Phase 4/5/8 handoff; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Reconcile Operations architecture, schema, contracts, workflows, access, events, files, cost, lineage, runbooks and evidence into a context-independent handoff.

## 5. Business value

Let Finance and later advanced-domain teams continue from one trusted checkpoint without rediscovery.

## 6. Source requirement

OPS-168..186; governance/context/status/ledger/change/error/issues/handoff contracts. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-186 VERIFIED; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-188; Steps 9,10,13; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Operations Completion schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

No feature schema by default; document authoritative entities, constraints, migrations, RLS, event/idempotency, money, lineage and recovery behavior.

## 14. API impact

Document REST/GraphQL/shared-service contracts, errors, jobs/webhooks, public tracking, file/ePOD access and Finance/advanced compatibility.

## 15. UI/UX impact

Document routes/workflows, roles, complete states, online-first responsive/accessibility behavior and customer/public surfaces.

## 16. Security impact

Document tenant/customer/organizational/field/record scopes, tokens, locations/PII/cost, files and RPD-022 exception. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Document baselines/budgets, event/timeline/query/upload/tracking/report limits, caches/timeouts and scale thresholds.

## 18. Audit impact

Reconcile audit events, evidence locations, privileged access, ePOD/cost/readiness/override trails and limitations.

## 19. Data migration impact

Document install/rebuild/upgrade/rollback/forward-fix, legacy reconciliation, fixtures/seeds and last trusted schema checkpoint.

## 20. Detailed implementation tasks

1. Reconcile context/status/WBS/task/change/decision/error/issues and traceability against actual checkpoint.
2. Update architecture/schema/data-flow/API/UI/access/event/file/money/lineage/report/runbook documents.
3. Create Phase 4 billing-readiness, Phase 5 advanced TMS/WMS and Phase 8 portal contract examples/boundaries.
4. Index tests/commands/evidence and disclose residual risks/accepted decisions.
5. Produce context-independent handoff and mark OPS-188 eligible only after readback consistency.

## 21. Main flow

All durable documents match verified code/schema/contracts/evidence and identify one exact checkpoint plus next closure task.

## 22. Alternative flow

A bounded residual documentation gap is assigned with impact and phase stays partial.

## 23. Exception flow

Contradictory schema/API/state/evidence, missing rollback, unknown issue or stale handoff blocks closure.

## 24. Business rules

- Documentation describes verified reality, not intended behavior.
- No secret, customer PII or unsafe credential/example enters docs.
- Package, runtime and production/GA states remain distinct.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Every requirement/capability/task links to implementation/evidence or explicit gap.
- Files/routes/migrations/commands/states match repository readback.
- Later phases receive exact contract versions, fixtures, boundaries and eligibility gate.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Store docs/evidence under repository policy; redact secrets/PII and restrict sensitive security evidence. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Use synthetic/redacted examples for land/air/sea, exception/ePOD/cost/readiness and handoff flows. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Documentation link/schema/contract/example/readback validation.
- Handoff reconstruction by a context-free reviewer or scripted checklist.
- Final smoke/regression/evidence-index integrity checks.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

All governance/control/build-log/API/schema/user/admin/support docs and downstream inputs. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-187.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Durable docs reconstruct the verified Operations checkpoint without chat context.
- All evidence, boundaries, residual risks and recovery paths are findable.
- Closure and later-phase handoff inputs are exact and ready.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-022` / `OPS-188` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

