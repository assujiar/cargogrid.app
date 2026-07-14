# Prompt 160 — Commercial Lineage into Job Order

**Prompt ID:** `CG-S7-COM-019`  
**Package document:** `CG-AABPP-COM-160`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-160.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-019` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Lineage and Data Quality; Epic: Commercial to Operations Handoff; Capability: Full accepted-quote lineage into Job Order; Feature slice: Accepted quote/customer/contract/credit snapshot→idempotent JobOrderDraftInput handoff; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement Commercial-owned end-to-end lineage and the idempotent accepted-quote conversion contract consumed by Phase 3 Job Order.

## 5. Business value

Let Operations start from trusted customer, contact, address, cargo, service, rate, price, acceptance and credit data without re-entry.

## 6. Source requirement

COM-QTN-001..004; COM-CPR-001..004; CPD-018/022; Brief §6; Master Prompt critical E2E. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-143..159; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-161..165; Step 8 Operations; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Lineage and Data Quality schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend conversion intent/outbox or handoff record, stable lineage edges, source-version manifest, immutable-for-normal-role snapshot, idempotency key, outcome/status and downstream reference placeholder.

## 14. API impact

Provide a versioned internal/shared-service conversion prepare/validate/commit/retry/status contract; REST/GraphQL exposure only where authorized and never duplicates Operations logic.

## 15. UI/UX impact

Build permitted conversion preview/status/retry surface showing inherited data, missing blockers, source links and downstream outcome; no Job Order editor here.

## 16. Security impact

Revalidate tenant/customer/record/field permissions and credit/acceptance eligibility at conversion; do not leak restricted cost/margin into Operations payload. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Bound snapshot size, index source/idempotency/status, use durable PostgreSQL jobs/outbox where asynchronous and prevent duplicate downstream creation.

## 18. Audit impact

Record initiator, exact source/version manifest, payload schema version/hash, validation, idempotency, attempts, downstream reference and failures/recovery.

## 19. Data migration impact

Backfill lineage only when source quote/customer/job references are provable; ambiguous historical jobs remain explicitly unreconciled.

## 20. Detailed implementation tasks

1. Define versioned JobOrderDraftInput and Commercial/Operations ownership contract.
2. Map accepted quote, customer/account/contact/site, cargo/service, selling/rate, contract and credit snapshots with field policy.
3. Implement idempotent prepare/validate/handoff/status/retry and durable failure recovery.
4. Build conversion preview/status UX and contract fixtures for Step 8 consumer.
5. Verify lineage completeness, no restricted leakage, duplicate prevention and compatibility.

## 21. Main flow

Authorized conversion prepares one validated source manifest and creates/delivers one idempotent Job Order input reference for Step 8 consumption.

## 22. Alternative flow

Retry with the same key reconciles prior outcome; compatible later consumer can process the stored versioned contract.

## 23. Exception flow

Unaccepted/stale quote, invalid customer/credit/contract, missing mandatory field, incompatible schema or downstream failure remains recoverable without duplicate Job Order.

## 24. Business rules

- Commercial owns source snapshot/lineage; Operations owns Job Order domain and lifecycle.
- Accepted quote/customer/contact/address/cargo/service/rate/price are referenced or governed snapshots, never retyped.
- One accepted quote/version plus conversion purpose/key cannot create duplicate downstream outcome.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Require accepted approved version, converted customer, effective pricing/credit result and complete operational inputs.
- Validate payload schema/version, source hashes/IDs, tenant/access and restricted-field projection.
- Reconcile every payload field to a canonical source/version or explicit justified override.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Authorized Commercial conversion roles initiate; Operations consumer receives only required permitted fields; cost/margin/credit detail remains minimized. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Complete/incomplete accepted quotes, customer sites/contacts, rate/pricing/credit snapshots, retries, schema mismatch, downstream failure and two tenants. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Lineage manifest/payload/idempotency/outbox/retry/compatibility/database tests.
- RLS/RBAC/field/record/cross-tenant/API/event/audit tests.
- Preview/status/retry E2E, contract consumer fixture, performance and critical-flow regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

All Commercial sources, job framework, API/webhook primitives and future Step 8 Job Order contract. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-160.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Every handoff field has canonical source/version lineage.
- Retries never duplicate downstream intent/outcome.
- Phase 2 does not implement or fork the Job Order domain.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-020` / `COM-161` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

