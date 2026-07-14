# Prompt 148 — RFQ and Costing Request

**Prompt ID:** `CG-S7-COM-007`  
**Package document:** `CG-AABPP-COM-148`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-148.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-007` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Costing and Pricing; Epic: Commercial Costing; Capability: RFQ and costing request; Feature slice: Opportunity requirements→cost request→response set→commercial feasibility; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement Commercial costing requests that inherit opportunity requirements and obtain governed internal/vendor cost responses without implementing full procurement RFQ.

## 5. Business value

Shorten quote turnaround while preserving a single requirements snapshot and clear Commercial–Procurement boundary.

## 6. Source requirement

COM-OPP-001..004; Brief §7.1 Quotation/§7.2 Costing; ASM-PK-004; CON-006. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-147; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-149..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Costing and Pricing schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend tenant-scoped costing request, versioned requirement snapshot, requested component, assignee, response, validity, status/SLA and opportunity link with idempotency/uniqueness constraints.

## 14. API impact

Expose shared REST/GraphQL request, assign, respond, revise, cancel and status operations; notifications/jobs manage SLA and retries.

## 15. UI/UX impact

Build accessible Request Costing step form, queue/detail/comparison-ready response view with inherited fields, clone/cancel and complete states.

## 16. Security impact

Separate sales request visibility from cost-entry/approval permissions; protect vendor cost and margin fields through server field policy. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/status/assignee/opportunity/due/service/lane; paginate queues and bound response/component loading.

## 18. Audit impact

Record inherited source versions, request/revision, component changes, assignments, responses, validity, cancellations and access to sensitive cost.

## 19. Data migration impact

Additive schema; map existing cost requests only with opportunity/source snapshot and currency/component reconciliation.

## 20. Detailed implementation tasks

1. Define Commercial costing boundary, status/SLA and requirement snapshot contract.
2. Implement idempotent opportunity-to-cost-request creation without retyping.
3. Implement response/revision/cancel/assignment and notification workflow.
4. Build progressive request/queue/detail UI and REST/GraphQL contracts.
5. Verify source snapshot, cost-field access, concurrency, audit and rate-lookup readiness.

## 21. Main flow

Seller submits inherited opportunity requirements; pricing/procurement returns valid componentized cost responses for lookup and margin.

## 22. Alternative flow

Request is revised or cloned into a new version while prior response evidence remains linked.

## 23. Exception flow

Missing dimensions/service/lane, invalid currency, expired response, unauthorized cost access or procurement dependency failure blocks safely.

## 24. Business rules

- This is a Commercial cost request, not full procurement sourcing/PO/vendor onboarding.
- Each request pins source opportunity and configuration versions.
- Responses retain vendor/internal source, validity, currency and component lineage.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Require service, origin/destination, cargo/weight/volume, SLA and applicable accessorial inputs.
- Validate response currency, effective/expiry dates, component totals and authorization.
- Revisions never overwrite a response used by an issued quote.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Sales creates/views request status; pricing/procurement enters cost by scope; only authorized roles see detailed cost/margin. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Complete/incomplete opportunities, internal/vendor responses, mixed components/currencies, expiry, revision, concurrent response and hidden costs. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Request snapshot/status/SLA/response/version/constraint tests.
- Cost-field/RLS/RBAC/record/cross-tenant/API parity/job/audit tests.
- Request form/queue/detail E2E, accessibility, concurrency and no-reentry regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Opportunity, notification/job engines, document/file access, later Procurement ownership and quote inputs. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-148.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Cost request reuses opportunity data and preserves immutable source/version links.
- Responses are componentized, valid, permission-safe and ready for lookup.
- No full procurement capability or duplicate vendor/rate model is introduced.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-008` / `COM-149` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

