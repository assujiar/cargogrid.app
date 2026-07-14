# Prompt 154 — Customer Acceptance

**Prompt ID:** `CG-S7-COM-013`  
**Package document:** `CG-AABPP-COM-154`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-154.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-013` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Quotation Lifecycle; Epic: Customer Commitment; Capability: Quotation send, acceptance, rejection and expiry; Feature slice: Approved quote→secure delivery→authorized customer decision→locked evidence; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement secure quotation delivery and explicit customer acceptance/rejection/expiry evidence bound to one approved version.

## 5. Business value

Create a reliable customer commitment that can drive customer/contract/Job Order conversion.

## 6. Source requirement

COM-QTN-001..004; Brief §§6,7.1; UX Commercial flow. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-153; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-155..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Quotation Lifecycle schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend send event, recipient/authority, delivery channel, secure token/session reference, decision, timestamp, reason, acceptance evidence, expiry and quote-version uniqueness constraints.

## 14. API impact

Provide idempotent shared internal send/resend/revoke and scoped customer accept/reject operations; webhook/integration callbacks are authenticated and replay-safe.

## 15. UI/UX impact

Build accessible send confirmation/status and customer decision surface with exact quote version, terms, expiry, explicit consent and complete states.

## 16. Security impact

Use short-lived scoped tokens/session, rate limits, CSRF/replay protection and customer/account authorization; private documents remain signed-URL protected and scanned. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/quote/version/status/expiry/token hash; schedule bounded expiry/reminder jobs and avoid synchronous provider dependence.

## 18. Audit impact

Record sender, recipients, channel, document/version, delivery events, customer actor/authority/IP/device where lawful, decision/reason and token lifecycle.

## 19. Data migration impact

Legacy accepted quotes require evidence/version reconciliation; unknown acceptance may not be promoted automatically.

## 20. Detailed implementation tasks

1. Define send/delivery/accept/reject/expire/revoke states and evidence contract.
2. Implement secure delivery and idempotent scoped decision operations.
3. Implement expiry/reminder/resend/revoke jobs and replay protection.
4. Build internal send/status and customer decision UX/API.
5. Verify actor authority, exact version, documents, audit and conversion eligibility.

## 21. Main flow

Approved quote is securely sent; an authorized customer explicitly accepts the exact unexpired version and evidence is locked for normal roles.

## 22. Alternative flow

Customer rejects with reason or seller resends/revokes before decision under policy.

## 23. Exception flow

Expired/revoked/wrong version, unauthorized actor, replay, delivery failure or concurrent accept/reject is rejected safely.

## 24. Business rules

- Delivery/read is not acceptance; acceptance requires explicit action and authority.
- One final customer decision binds one exact approved version; later revision needs new approval/acceptance.
- Normal-role acceptance evidence cannot be overwritten; RPD-022 exception remains disclosed.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Verify quote approval, current version eligibility, expiry, recipient/account authority and token/session scope.
- Decision is atomic, idempotent and mutually exclusive.
- Acceptance evidence includes required legal/contract fields configured for the tenant.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Sales controls permitted send actions; customer decision scope is account/contact-specific; cost/margin never appears in customer projection. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Multiple recipients, expired/revoked token, resend, reject reason, concurrent accept/reject, wrong account, replay and scanned/private document. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Send/token/expiry/decision/idempotency/concurrency/quote-version constraint tests.
- Customer-scope/RLS/RBAC/field/API/webhook/file/audit/security tests.
- Send/status/customer-decision E2E, accessibility, expiry job and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Quote approval/version/document, contacts/preferences, notification jobs, custom domain and future Customer Portal. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-154.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- Acceptance is explicit, authorized and bound to the correct quote version.
- Replay, expiry and cross-customer attempts fail without leakage.
- Accepted result is conversion-ready with complete evidence.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-014` / `COM-155` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

