# Prompt 181 — Billing Readiness

**Prompt ID:** `CG-S8-OPS-015`  
**Package document:** `CG-AABPP-OPS-181`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-181.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-015` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Job Completion; Epic: Finance Handoff; Capability: Versioned billing readiness evaluation; Feature slice: Delivered/ePOD/docs/cost/customer evidence→ready/not-ready reasons→Finance handoff; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement a versioned billing-readiness checklist and evaluation that exposes exact blockers and a stable Phase 4 input without creating invoices.

## 5. Business value

Reduce delay between operational completion and controlled Finance billing.

## 6. Source requirement

OPS-CST-001..004 basic slice; OPS-DOC-001..004; Charter/UX ePOD→billing readiness; Phase 4 boundary. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-168..179; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-182..188; Step 9 Finance; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Job Completion schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Add/extend readiness rule/config version, job/shipment evaluation, evidence manifest, ready/not-ready status, reasons, evaluated time, override/reopen and Finance handoff reference constraints.

## 14. API impact

Provide shared REST/GraphQL evaluate, explain, reevaluate, authorized override/revoke, queue and Phase 4 handoff operations.

## 15. UI/UX impact

Build accessible Operations readiness checklist and queue with evidence links, blocker reasons, override/reopen controls and complete states.

## 16. Security impact

Protect customer billing profile, selling/cost amounts and documents; Finance/Operations actions use separate scopes and file access. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/status/customer/branch/evaluated time; evaluate incrementally/event-driven and batch via durable jobs for large queues.

## 18. Audit impact

Record rule/config/source versions, evidence checks, outcomes/reasons, actor/job, override/revoke and Finance handoff attempts.

## 19. Data migration impact

Map legacy billing flags only with evidence/rule provenance; unknown flags become not-evaluated rather than ready.

## 20. Detailed implementation tasks

1. Define readiness evidence/rules and Operations-versus-Finance ownership boundary.
2. Implement deterministic versioned evaluation and exact blocker reasons.
3. Implement queue, reevaluation, bounded override/revoke and idempotent Phase 4 handoff.
4. Build checklist/queue UX and shared API contracts.
5. Verify evidence lineage, access, concurrency, performance and no invoice/AR/GL scope.

## 21. Main flow

Delivered job with complete ePOD/documents, required cost/customer/billing evidence evaluates ready and produces one versioned Finance handoff.

## 22. Alternative flow

Authorized override marks a bounded readiness outcome with reason/approval; later evidence change reevaluates/revokes under policy.

## 23. Exception flow

Missing/rejected/quarantined/expired document, incomplete ePOD, active blocker, missing billing profile/cost or stale rule stays not-ready.

## 24. Business rules

- Billing readiness is evidence status, not invoice, accounts receivable (AR), general ledger (GL), revenue recognition or journal posting.
- Every ready outcome pins rule/config and source evidence versions.
- Evidence changes do not silently preserve readiness; explicit reevaluation/revoke policy applies.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Validate required shipment/job state, ePOD, document checklist, active exceptions, customer billing profile and cost evidence.
- Reconcile ready queue to source evidence and current access.
- Handoff is idempotent and contains source IDs/versions, never duplicate billing data.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Operations resolves operational blockers; authorized Finance reads/consumes readiness; overrides require elevated governed permission. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Ready and each blocker type, multiple shipments/ePODs, quarantined/expired docs, active exception, missing cost/profile, overrides and concurrent evaluation. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Rule/evidence/status/reason/reevaluation/override/handoff/idempotency/database tests.
- RLS/RBAC/field/record/file/cross-tenant/API parity/audit tests.
- Checklist/queue E2E, accessibility, batch performance and no-invoice-scope regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Job/shipment/ePOD/documents/exceptions/cost/profitability/customer data and Step 9 Finance contract. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-181.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Readiness is deterministic, explainable and source-versioned.
- Not-ready records expose exact recoverable blockers.
- No invoice, accounts receivable (AR), general ledger (GL) entry or journal is created in Phase 3.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-016` / `OPS-182` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.
