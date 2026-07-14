# Template 63 — Financial Posting

**Prompt ID:** `CG-S4-REUSE-011`  
**Package document:** `CG-AABPP-REUSE-063`  
**Version:** `0.5.0`  
**Intended use:** Implement one bounded double-entry posting, reversal or allocation capability.

## Paste-ready prompt

Do not begin implementation until every variable is resolved, runtime discovery and architecture closures are verified, the applicable phase package authorizes this task, and `TASK_LEDGER.md` marks it `READY`. If any gate fails, record `BLOCKED` and stop.

## 1. Prompt ID

`{{PROMPT_ID}}` — must map to one approved WBS/task-ledger item.

## 2. Parent phase

`{{PARENT_PHASE}}`; phase package/version: `{{PHASE_PACKAGE_VERSION}}`.

## 3. Workstream

Finance and Financial Integrity.

## 4. Objective

Implement {{POSTING_EVENT}} with balanced, idempotent, locked-period-aware, reversible and reconcilable accounting.

## 5. Business value

Create trustworthy financial lineage from business event through subledger and GL without duplicate or unbalanced entries.

## 6. Source requirement

{{FIN_REQUIREMENT_IDS}}, {{POSTING_RULE_ID}}, {{WBS_TASK_ID}}. Cite exact CPD/RPD/requirement/business-rule/ADR/runtime evidence; do not rely on chat.

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

Use transactional journal/header/line/subledger structures, unique idempotency, immutable-for-normal-role posted state and tenant-aware constraints/RLS.

## 14. API impact

Expose controlled preview/post/reverse/status contract with concurrency, idempotency and safe errors.

## 15. UI/UX impact

Provide draft/preview/approval/post/reversal/reconciliation states, amounts/currency/rates and permission-denied behavior.

## 16. Security impact

Enforce finance roles/scopes, separation of duties, field masking and server-only posting; disclose Supreme Admin absolute CRUD risk.

## 17. Performance impact

Bound posting batches, locking and reconciliation queries; measure concurrency and index paths.

## 18. Audit impact

Record source event, rule/config version, actor/approver, posting/reversal links, period/rate/rounding and before/after state.

## 19. Data migration impact

Posting backfill requires separate approved data-migration task, dry run, idempotency and reconciliation; never fabricate opening balances.

## 20. Detailed implementation tasks

1. Define event-to-account mapping, dimensions, currency/rate/rounding, dates and billing-readiness/period rules.
2. Implement transactional preview/post with balanced lines and unique source/idempotency key.
3. Implement permitted reversal/adjustment, lock checks, subledger/GL linkage and reconciliation.
4. Add concurrency, duplicate, failure injection and Supreme Admin risk evidence.
5. Compare baseline/post-change evidence and update persistent records; do not expand scope to adjacent defects.

## 21. Main flow

Eligible authorized event posts exactly once with debit=credit and full source lineage.

## 22. Alternative flow

Approved adjustment/reversal or multi-currency allocation produces linked balanced entries.

## 23. Exception flow

Duplicate, unbalanced, closed period, invalid account/rate/tax, concurrency and partial dependency fail atomically.

## 24. Business rules

- Posted journals are not edited by normal roles; corrections use reversal/adjustment.
- RPD-022 means Supreme Admin can alter records, so immutable/tamper-proof claims are forbidden.
- Preserve canonical entities/statuses, configuration version/effective date and cited approval rules.

## 25. Validation rules

- Debit equals credit per journal/currency rules; period, account, tax, rounding, source and uniqueness checks are enforced.
- Subledger, AR/AP, cash/bank and GL reconciliation invariants hold.
- Validate on trusted server/database boundaries; never rely on client-only checks.

## 26. Access rules

- Map prepare/approve/post/reverse/unlock/view/export fields with separation of duties and tenant isolation.
- Enforce least privilege, strict tenant isolation, RLS, RBAC plus scope, field/record access and server-only service role.

## 27. Test data requirement

Two tenants, currencies/rates/rounding, open/closed periods, duplicate source, concurrent posting, tax, partial allocation and reversal cases. Use synthetic/redacted data only; never commit real tenant, credential, payroll, tax, bank or personal data.

## 28. Tests to create/update

- Balance, idempotency, concurrency, period lock, reversal/adjustment and reconciliation tests.
- RLS/RBAC/field access, audit lineage, API/UI flow, failure atomicity and performance tests.
- Include main, alternative, exception, audit and negative security evidence proportional to risk.

## 29. Regression tests

- AR/AP/receipt/allocation, profitability, close, reports, exports and existing journals.
- Compare baseline failures separately; never disable or weaken tests, lint, typecheck, RLS or validation.

## 30. Commands to run

Use the detected package manager and repository scripts. Run scoped checks during work, then applicable lint, typecheck, unit/integration/contract/E2E, migration/RLS/security/performance/accessibility and build gates. Record exact redacted commands, exit codes, counts, durations and artifacts; do not blindly substitute npm or auto-install tooling.

## 31. Documentation to update

Update `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, task build log, `CHANGE_MANIFEST.md`, `REGRESSION_MATRIX.md`, `REQUIREMENT_TRACEABILITY_MATRIX.md`, and relevant schema/API/data-flow/module-dependency/decision/assumption/error/issues/user/admin/API/support/release docs. Documentation is part of completion.

## 32. Rollback/recovery note

Preserve the last known good checkpoint. Define code, schema, data, flag and contract rollback/forward-fix steps; stop on partial/unsafe state, update error/issues/handoff records, and create a bounded resume prompt.

## 33. Acceptance criteria

- All entries balance and reconcile; duplicates/closed periods/unauthorized actions fail safely.
- Lineage, reversal, lock, audit and accepted-risk evidence passes.
- Mandatory gates pass with no hidden failures or unauthorized changes.

## 34. Definition of Done

Implementation, positive/negative/regression evidence, security/performance/audit checks, documentation, change manifest, task ledger, checkpoint and handoff are reconciled. Status is `VERIFIED`, not merely code complete; production/market/GA claims remain prohibited without release gates.

## 35. Completion report format

Report task/checkpoint/status; objective/source; baseline; scope/files/migrations/routes/contracts; database/RLS/RBAC/API/UI/security/performance/audit/data effects; tests and exact commands/results; documentation; errors/recovery; residual risks/known issues; rollback readiness; commit/branch; and next eligible task.

## 36. Next eligible prompt

`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance and dependencies pass. Otherwise output the exact `BLOCKED`, `FAILED`, or `PARTIALLY_COMPLETE` resume prompt and stop.
