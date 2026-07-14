# Prompt 153 — Quotation Approval

**Prompt ID:** `CG-S7-COM-012`  
**Package document:** `CG-AABPP-COM-153`  
**Version:** `0.8.0`  
**Runtime build log:** `docs/build-log/phase-02/COM-153.md`

Do not begin until Prompt 142 marks this task `READY`, all variables are resolved, and `PHASE_1_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S7-COM-012` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 2 — Commercial MVP`; package `0.8.0`.

## 3. Workstream

Workstream: Quotation Lifecycle; Epic: Commercial Governance; Capability: Quotation approval and exception control; Feature slice: Submitted quote→threshold routing→approve/reject/revise/escalate; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement configurable quotation approval driven by margin, discount, value, customer, service and organizational thresholds.

## 5. Business value

Prevent unauthorized commercial commitments while keeping approval timely, explainable and auditable.

## 6. Source requirement

COM-QTN-001..004; Brief §7.1 Quotation; Platform approval/workflow engines. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 2 execution index, source requirements and relevant prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/data/financial/security/ownership conflict.

## 9. Upstream dependencies

COM-150..152; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

COM-154..161; identify schemas, services, REST/GraphQL, jobs/files, portals, analytics, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Quotation Lifecycle schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Operations/Finance/Procurement implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1 contracts.

## 13. Database impact

Add/extend quote approval instance/step references to published workflow/rule versions, decision, delegation, escalation, SLA, comments and locked quote version.

## 14. API impact

Provide shared REST/GraphQL submit, approve, reject, request-revision, delegate and escalate operations through the Platform approval engine.

## 15. UI/UX impact

Build accessible approval inbox/detail/diff with cost/margin fields projected by permission, SLA indicators and complete decision states.

## 16. Security impact

Approver eligibility, separation of duty, delegation and field projections are server authoritative; requester cannot self-approve unless an explicit rule permits. Preserve tenant isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Index tenant/approver/status/due/value; paginate inbox and precompute permitted summaries without leaking hidden margin/cost.

## 18. Audit impact

Record rule/workflow version, threshold inputs, approver resolution, every decision/comment/delegation/escalation and final approved quote hash/reference.

## 19. Data migration impact

Adopt open approvals only when quote version and workflow step can be reconciled; never auto-approve legacy records.

## 20. Detailed implementation tasks

1. Define quote approval triggers, thresholds, separation and state transitions.
2. Instantiate Platform workflow/approval engine with pinned quote/rule versions.
3. Implement decisions, delegation, SLA escalation and revision return.
4. Build approval inbox/detail/diff UX and shared API contracts.
5. Verify no bypass, field security, concurrency, audit and acceptance eligibility.

## 21. Main flow

Submitted quote resolves the correct approvers and becomes approved only after every required step passes.

## 22. Alternative flow

Approver rejects or requests revision; a new/revised quote returns through a fresh governed approval path.

## 23. Exception flow

Missing approver, stale quote, threshold conflict, self-approval violation, timeout or concurrent decision blocks safely.

## 24. Business rules

- Approval always binds one exact quote version and calculation snapshot.
- Threshold changes do not rewrite an in-flight approval unless an explicit reevaluation rule runs.
- Customer sending/acceptance is blocked until required approval is complete.
- One shared multi-tenant codebase; preserve canonical status, entitlement and CPD/RPD decisions.

## 25. Validation rules

- Resolve approver eligibility and threshold inputs server-side at submit/decision time.
- Decision is idempotent and rejects stale/already-completed steps.
- Approved outcome reconciles workflow, quote version, margin result and audit evidence.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Requesters see status; approvers see assigned details by field policy; managers/admins reassign only under governed rules. Enforce entitlement, tenant/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Above/below margin/value/discount thresholds, parallel/sequential approval, delegation, timeout, rejection/revision, self-approval and concurrent decisions. Use synthetic/redacted fixtures with at least two tenants and realistic organizational scopes.

## 28. Tests to create/update

- Approval resolution/state/SLA/idempotency/concurrency/quote-lock tests.
- RLS/RBAC/field/record/separation/API parity/notification/audit tests.
- Inbox/detail/diff E2E, accessibility, escalation-job and regression tests.
- Cover main/alternative/exception, idempotency/retry, concurrent request, import/export, background job, file access and abuse paths as applicable.

## 29. Regression tests

Platform approval/workflow, quote versioning, margin, notifications, customer send and reports. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-02/COM-153.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 2 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- No quote bypasses required approval or binds the wrong version.
- Decisions and escalations are deterministic, permission-safe and audited.
- Only valid approved versions become customer-acceptance eligible.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S7-COM-013` / `COM-154` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

