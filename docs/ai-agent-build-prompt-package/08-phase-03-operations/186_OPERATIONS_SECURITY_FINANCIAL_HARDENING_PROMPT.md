# Prompt 186 — Operations Tenant, Security, Financial and Data Hardening

**Prompt ID:** `CG-S8-OPS-020`  
**Package document:** `CG-AABPP-OPS-186`  
**Version:** `0.9.0`  
**Runtime build log:** `docs/build-log/phase-03/OPS-186.md`

Do not begin until Prompt 167 marks this task `READY`, all variables are resolved, and `PHASE_2_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S8-OPS-020` and one WBS/task-ledger item.

## 2. Parent phase

`Phase 3 — Operations MVP`; package `0.9.0`.

## 3. Workstream

Workstream: Operations Completion; Epic: Risk Hardening; Capability: Evidence-ranked Operations hardening; Feature slice: Integrated findings→root-cause repair→regression proof; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Repair verified Operations blockers and high-risk tenant/customer, access, file/ePOD, money, lineage, API, performance and UX weaknesses without scope expansion.

## 5. Business value

Make the Operations increment dependable for Finance consumption and later advanced domains.

## 6. Source requirement

OPS-185 findings; security/data/financial guardrails; RPD-004/014/022/032/034/036. Cite exact runtime evidence, ADR, configuration version and prerequisite task IDs.

## 7. Current repository context

Record root/branch/HEAD/dirty ownership, runtime closure IDs, current schema/migrations/contracts/routes/modules, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read governance/context/status/task/decision/assumption/error/issues/handoff, Phase 3 execution index, source requirements and prior logs. Inspect repository/schema/API/UI/tests. Capture baseline, expected files/migrations and stop on tenant/customer/data/financial/security/phase-boundary conflict.

## 9. Upstream dependencies

OPS-185 VERIFIED with ranked findings; every prerequisite in the execution index must be `VERIFIED`.

## 10. Downstream impact

OPS-187..188; identify schemas, services, REST/GraphQL, jobs/files, tracking, Finance/advanced contracts, tests/docs and phase gates.

## 11. Allowed files/folders

Exact Operations Completion schema/migrations/service/UI/tests/docs paths from WBS. Resolve exact paths; normally 5–15 files and at most 1–3 migrations.

## 12. Forbidden files/folders

Unrelated domains, full Finance/WMS/advanced TMS/Customer Portal implementations, tenant forks, destructive cleanup and applied migrations. Preserve unrelated/user-owned changes, protected decisions and Phase 1–2 contracts.

## 13. Database impact

Apply only evidence-backed additive/expand-contract repairs to constraints, RLS, event/idempotency, money precision, indexes, lineage or recovery state.

## 14. API impact

Harden authorization, projection, idempotency, rate limits, public tokens, validation, error leakage, webhook/job retry and compatibility.

## 15. UI/UX impact

Harden field masking, stale/conflict/error states, online upload recovery, accessibility and responsive critical workflows.

## 16. Security impact

Prioritize tenant/customer isolation, IDOR, public enumeration, file/ePOD leakage, location/PII, cost/profitability and privileged-audit gaps. Preserve tenant/customer isolation, four-layer context, RBAC/RLS, field/record policy and server-only secrets.

## 17. Performance impact

Repair measured N+1/query/event/upload/tracking/export bottlenecks while preserving correctness and access.

## 18. Audit impact

Record each finding, root cause, changed control, before/after evidence, residual risk and RPD-022 limitations.

## 19. Data migration impact

Use reversible safe migrations, supported upgrade/rebuild tests and checkpointed data repair; never edit applied migrations.

## 20. Detailed implementation tasks

1. Rank OPS-185 findings by severity/exploitability/data/financial/downstream effect.
2. Trace each blocker to root cause and create bounded repair tasks.
3. Implement minimal authorized repairs with migration/contract/rollback compatibility.
4. Rerun targeted plus full affected isolation/file/money/lineage/E2E/regression gates.
5. Update errors/issues/risk/change evidence and determine documentation eligibility.

## 21. Main flow

Each critical/high finding is repaired at root cause and closed by reproducible regression evidence.

## 22. Alternative flow

Accepted noncritical residual risk has owner, rationale, workaround and later gate; phase remains honest.

## 23. Exception flow

Unbounded fix, data loss, failed migration, tenant/customer leak, ePOD exposure, money/lineage mismatch or authority conflict triggers rollback/resume.

## 24. Business rules

- Zero open critical tenant/customer/security/financial/lineage defect is required for closure.
- Hardening cannot add advanced TMS/WMS/full portal/Finance features or relax tests/access.
- RPD-022 means immutable/tamper-proof claims remain prohibited.
- One shared multi-tenant codebase; preserve canonical status, entitlement, no-reentry and CPD/RPD decisions.

## 25. Validation rules

- Before/after evidence reproduces and closes the exact finding.
- Repairs preserve no-reentry, Commercial source and Step 9/10/13 contracts.
- Residual issues have correct severity, owner, dependency and release effect.
- Validate server/database boundaries; no unresolved placeholder, float money or client-only business/access rule.

## 26. Access rules

Use isolated authorized environments/data; privileged testing is time/purpose bound and logged. Enforce entitlement, tenant/customer/organization scope, RBAC, RLS, field/record rules and RPD-022 disclosure.

## 27. Test data requirement

Abuse fixtures, boundary money, duplicate/concurrent events/conversions, malicious files/tokens, large timelines/reports and migration checkpoints. Use synthetic/redacted fixtures with at least two tenants, two customers and realistic organizational scopes.

## 28. Tests to create/update

- Targeted root-cause tests for every repaired finding.
- Full tenant/customer/RLS/RBAC/field/record/API/file/money/lineage/E2E regression.
- Migration rollback/forward-fix, accessibility, performance and smoke gates.
- Cover main/alternative/exception, idempotency/retry, concurrency, import/export, background jobs, file access and abuse paths as applicable.

## 29. Regression tests

Platform Core, Commercial, all Operations capabilities, Step 9/10/13 contracts and persistent governance docs. Separate pre-existing failures; never weaken tests, RLS/RBAC, financial precision, validation, file policy or lineage.

## 30. Commands to run

Use detected package manager/scripts. Run scoped and applicable lint, typecheck, unit/integration/contract, migration rebuild/upgrade, RLS/RBAC/field/record/customer/cross-tenant, E2E/accessibility/performance/security and build gates. Record exact commands/results; no unsafe auto-install or shared DB.

## 31. Documentation to update

Update context/status/task ledger, `docs/build-log/phase-03/OPS-186.md`, change manifest, regression/traceability/schema/API/data-flow/module/decision/error/issues/user/admin/API/support docs and Phase 3 handoff.

## 32. Rollback/recovery note

Preserve last trusted checkpoint. Define exact code/schema/data/contract/config/job/file/flag rollback or forward-fix; stop on partial/untrusted state and create a bounded resume prompt.

## 33. Acceptance criteria

- No critical/high closure blocker remains without explicit blocking state.
- Repairs are bounded, reversible and regression-proven.
- Residual risk and RPD-022/online-first/direct-GA disclosures are complete.
- Mandatory gates pass, worktree/schema/docs reconcile and no unauthorized scope changed.

## 34. Definition of Done

Task is `VERIFIED` only after implementation, positive/negative/regression evidence, security/performance/audit/data integrity, docs, ledgers, checkpoint and handoff agree. Phase completion/readiness is not implied.

## 35. Completion report format

Report task/checkpoint/status; hierarchy/objective/source; baseline; files/migrations/contracts/routes; DB/RLS/RBAC/API/UI/security/performance/audit/data; tests/commands; docs; errors/recovery; risks; rollback; branch/commit; next prompt.

## 36. Next eligible prompt

`CG-S8-OPS-021` / `OPS-187` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.

