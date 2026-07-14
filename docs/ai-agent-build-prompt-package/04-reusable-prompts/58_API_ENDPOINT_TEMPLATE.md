# Template 58 — API Endpoint

**Prompt ID:** `CG-S4-REUSE-006`  
**Package document:** `CG-AABPP-REUSE-058`  
**Version:** `0.5.0`  
**Intended use:** Implement one REST endpoint or GraphQL operation over an approved domain service.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

API and Integration.

## 4. Objective

Implement {{API_OPERATION}} with stable contract, tenant authorization, validation, idempotency and compatibility.

## 5. Business value

Expose a reliable integration contract without duplicating domain rules or leaking tenant data.

## 6. Source requirement

{{API_REQUIREMENT_IDS}}, {{CONTRACT_ID}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-state ownership, architecture/discovery closure IDs, module boundary, current implementation/contracts, package manager, framework/database versions, environment and last trusted checkpoint.

## 8. Preconditions

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, relevant phase build log and source requirements. Inspect repository; detect package manager/scripts; capture baseline gates; write a short plan and expected files. Stop on tenant, data or finance integrity conflict.

## 9. Upstream dependencies

`{{UPSTREAM_TASK_IDS}}`, approved ADRs/migrations/contracts, verified runtime gates and baseline evidence. All must be satisfied or explicitly blocking.

## 10. Downstream impact

`{{DOWNSTREAM_TASK_IDS_AND_CONSUMERS}}`. Identify contracts, modules, jobs, reports, portals, migrations, docs and release gates affected.

## 11. Allowed files/folders

`{{EXACT_ALLOWED_PATHS}}`; normally 5–15 files, one module boundary and at most 1–3 approved migrations. User-owned unrelated changes are excluded.

## 12. Forbidden files/folders

`{{EXACT_FORBIDDEN_PATHS}}`; always exclude unrelated modules, applied migrations, lockfiles unless dependency scope is explicit, secrets, generated artifacts unless authorized, tenant data, and broad refactors.

## 13. Database impact

Use approved domain repository/service; tenant-safe transactions, constraints and pagination. No direct unbounded query.

## 14. API impact

Primary scope: REST/GraphQL schema, versioning, input/output/error contract, pagination, concurrency, idempotency and deprecation.

## 15. UI/UX impact

Document consumer impact; UI changes require separate scope unless explicitly authorized.

## 16. Security impact

Authenticate and authorize tenant/role/scope/field/record; rate-limit and prevent IDOR/injection/SSRF/mass assignment.

## 17. Performance impact

Bound request/payload/query complexity; server pagination, timeouts/cancellation, no N+1 or SELECT *.

## 18. Audit impact

Log correlation, privileged/mutating actions, outcome and safe error context without secrets/PII.

## 19. Data migration impact

Contract rollout may require additive schema migration; coordinate compatibility window.

## 20. Detailed implementation tasks

1. Define contract/examples/errors and shared domain-service ownership.
2. Implement operation with validation, authorization, transaction/idempotency and observability.
3. For GraphQL enforce field authorization, depth/complexity and resolver batching; for REST enforce resource/version semantics.
4. Update OpenAPI/GraphQL docs and consumer compatibility tests.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Authorized request returns the documented result exactly once within limits.

## 22. Alternative flow

Pagination/filter/sort, conditional/concurrent or asynchronous accepted response follows contract.

## 23. Exception flow

Invalid, unauthenticated, unauthorized, missing, conflict, duplicate, rate-limit, timeout and internal failures use safe stable errors.

## 24. Business rules

- REST and GraphQL invoke the same business rules; interface parity cannot create bypass.
- Breaking changes require approved version/deprecation and consumer migration.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Strict schemas reject unknown/invalid input and mass assignment.
- Idempotency/concurrency semantics are deterministic.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Map operation and field/record access for all principals; hide existence when required.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Two tenants, roles/scopes, valid/invalid payloads, large page, duplicate keys, concurrent requests and sensitive fields. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Contract/schema, service/integration, database/RLS and REST/GraphQL parity tests.
- Auth, IDOR, injection, rate-limit, idempotency, concurrency and performance tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- Existing clients, webhooks/jobs, exports, UI consumers and API documentation examples.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- Contract, authorization, idempotency and compatibility evidence passes.
- No tenant/field leakage, N+1, unbounded payload or undocumented behavior.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
