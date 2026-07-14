# Prompt 157 — Credit and Commercial Control

**Prompt ID:** `CG-S7-COM-016`  
**Package document:** `CG-AABPP-COM-157`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-157.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-016` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Customer and Contract; Epic: Commercial Risk; Capability: Credit limit, status, hold and override; Feature slice: Customer credit profile→commercial check→hold/approve/override snapshot; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement Commercial credit profile and transaction eligibility controls with exact limits, approval, hold and reasoned override while deferring AR/GL posting to Phase 4.

## 5. Business value

Prevent unauthorized exposure and make credit assumptions visible before operational conversion.

## 6. Source requirement

COM-CPR-001..004; Brief §11 Customer Data; UX credit_limit field; Finance boundary. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-155..156; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-158..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Customer and Contract schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend tenant/customer/company-scoped credit profile, currency, requested/approved limit, status, effective dates, hold reason, approval reference, override and check snapshot/version.

## 14. API impact

Provide shared REST/GraphQL request/review/approve/hold/release/check/override operations; expose a stable Finance integration contract without synthetic balances.

## 15. UI/UX impact

Build accessible credit profile/review and commercial check result with restricted fields, warnings, approval actions and complete states.

## 16. Security impact

Credit values/status/override are financial-sensitive fields; enforce finance/commercial permissions, separation, MFA for privileged approvers and export masking. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/customer/company/status/effective dates; keep checks deterministic and bounded; external balance lookup waits for Phase 4 contract.

## 18. Audit impact

Record request/limit/status/effective changes, approval, hold/release, check inputs/version/outcome and every override reason/authority.

## 19. Data migration impact

Map legacy limits/status only with currency/effective/source evidence; unknown exposure or balance stays explicitly unavailable.

## 20. Detailed implementation tasks

1. Define Commercial credit profile, state, limit currency and Phase 4 balance boundary.
2. Implement versioned request/approval/hold/release lifecycle through Platform approval engine.
3. Implement deterministic pre-conversion check and reasoned override snapshot.
4. Build restricted credit/review/check UX plus shared API contracts.
5. Verify precision, separation, MFA policy, access, audit and future Finance integration.

## 21. Main flow

Authorized approver activates a customer credit profile; commercial conversion checks the pinned rule/profile and returns allow/hold.

## 22. Alternative flow

Authorized override permits a bounded transaction with reason, amount, expiry and elevated approval.

## 23. Exception flow

Missing currency/profile, expired limit, hold, unauthorized override, stale version or unavailable required Finance signal blocks safely.

## 24. Business rules

- Customer creation does not imply credit approval.
- Phase 2 never invents AR exposure, payment or GL balances; unavailable data is explicit.
- Every operational handoff pins the credit-check outcome/version; later changes do not rewrite it.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Use exact decimal money, explicit currency and nonnegative limit.
- Validate state/effective dates, approval authority, override bounds/expiry and customer/company scope.
- Check outcome reconciles profile, contract value and available Finance signal policy.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Commercial may request/view allowed status; Finance/authorized approvers manage limits; detailed values and override need restricted field access/MFA. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Cash-only, requested/active/held/expired profiles, multiple currencies, below/above limit, unavailable exposure, overrides and cross-scope users. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Credit state/approval/effective/precision/check/override/database tests.
- RLS/RBAC/field/record/MFA-policy/API parity/audit tests.
- Credit/review/check E2E, accessibility, concurrency and customer/contract regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Customer conversion, contract pricing, approval engine, future Finance contracts and Job Order eligibility. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-157.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Credit eligibility is deterministic, versioned and never based on invented balances.
- Sensitive values and override actions are protected and audited.
- Operations can consume a stable check snapshot in Step 8.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-017` / `COM-158` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

