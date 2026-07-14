# Prompt 246 — Advanced TMS/WMS Integrity and Security Hardening

**Prompt ID:** `CG-S10-ATW-027`  
**Package document:** `CG-AABPP-ATW-246`  
**Version:** `0.11.0`  
**Runtime build log:** `docs/build-log/phase-05/ATW-246.md`

Do not begin until ATW-245 is `VERIFIED`, its findings are triaged, and `PHASE_4_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S10-ATW-027` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 5 — Advanced TMS and WMS`; package `0.11.0`.

## 3. Workstream

Workstream: Phase 5 Assurance; Epic: Integrity and Security Hardening; Capability: Findings Remediation and Adversarial Reverification; Feature slice: data invariants, authorization, files/integrations, concurrency, recovery and residual risk; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Repair every Phase 5 blocking finding, harden high-risk boundaries and prove the fixes without expanding functional scope.

## 5. Business value

Reduce the chance that transport or warehouse defects cause cross-customer exposure, stock corruption, duplicate activity or financial inconsistency.

## 6. Source requirement

ATW-245 findings plus all Phase 5 OPS/RPD controls, especially RPD-001/002/014/022/025/031/032/033/035/036/038. Cite exact finding/source and before/after evidence.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, tested checkpoint, open findings/closures, schemas/contracts/modules/jobs/integrations, package scripts, environment, baseline and trusted checkpoint.

## 8. Preconditions

Read all persistent ledgers, ATW-245 evidence/findings and relevant build logs. Map each blocker to root cause, owner, files, tests and rollback; reproduce before editing, state bounded plan, and stop if repair requires a new product decision or Step 11–14 scope.

## 9. Upstream dependencies

ATW-245 `VERIFIED` with all findings classified and blocking items assigned.

## 10. Downstream impact

ATW-247..248 and every repaired capability consumer. Invalidate and rerun all affected focused, integrated and Phase 1–4 regression gates.

## 11. Allowed files/folders

Only files directly required to remediate registered ATW-245 findings plus tests, migrations, runbooks and build logs. Keep diffs minimal and evidence-backed.

## 12. Forbidden files/folders

Unregistered feature work, Step 11–14 implementations, tenant forks, duplicate roots, security/test weakening, destructive cleanup, applied-migration edits, broad refactors without evidence and unrelated user changes.

## 13. Database impact

Harden constraints, RLS/policies, idempotency/version/state transitions, exact ledger equations, job leases and indexes only where a finding proves need. Use additive/expand-contract migration and reconcile before/after.

## 14. API impact

Repair shared service/auth/field-policy parity, validation, enumeration/errors, idempotency/concurrency, cursors/rate limits, callback signatures and failure semantics; update versioned contracts compatibly.

## 15. UI/UX impact

Repair misleading or missing states, unsafe actions, stale/conflict handling, scan/manual alternatives, responsive/accessibility defects and recovery messaging. Keep online-first PWA and no fake success/dead action.

## 16. Security impact

Adversarially test tenant/customer/warehouse/owner scope, scan/reference forgery, field/aggregate/export leakage, files/URLs, jobs/realtime/cache, webhook/telematics validation, secrets and privileged separation.

## 17. Performance impact

Confirm fixes do not regress declared target-volume budgets; rerun affected query plans, load/soak/failure tests and correctness reconciliation. Security controls must remain performant without unsafe bypass.

## 18. Audit impact

Ensure repaired actions preserve actor/context, source/config/version, idempotency/correlation, before/after/event chain, denial/failure and override evidence with appropriate redaction.

## 19. Data migration impact

Rehearse every repair migration on clean install and Phase 4/5 upgrade with lock/time/disk, backup, rollback/forward recovery and ledger/event reconciliation. Never rewrite applied migrations or fabricate history.

## 20. Detailed implementation tasks

- Reproduce and rank each ATW-245 blocker/root cause.
- Repair minimal code/schema/policy/config/docs and add a failing-then-passing regression.
- Run adversarial isolation, integrity, concurrency, file/integration and recovery tests.
- Rerun affected focused plus complete integrated critical gates.
- Close only findings with durable before/after evidence; document residual risks.

## 21. Main flow

For each registered finding, reproduce at the frozen checkpoint, implement a bounded repair, prove focused regression, rerun impacted integration/non-regression gates and close with evidence/reviewer.

## 22. Alternative flow

If a safe fix cannot land in scope, disable the affected capability only through an approved reversible control, document user impact and keep Phase 5 closure blocked unless the source gate explicitly allows it.

## 23. Exception flow

Stop on data-loss risk, ambiguous ownership, new decision, incompatible contract, unbackfillable constraint, unreconciled ledger/event, critical regression or evidence mismatch. Register issue and safe recovery; never waive silently.

## 24. Business rules

- Every change maps to an ATW-245 finding and has a regression test.
- Authorization and inventory/transport/Finance invariants are enforced server/database-side where applicable.
- Fixes preserve canonical roots, exact UOM/ledger, event order and idempotent handoffs.
- RPD-022 remains an explicit residual risk; do not claim universal immutability/tamper proof.
- No tenant fork, autonomous legal/routing/pricing commitment, offline sync or partial-GA claim.
- Phase boundaries remain Step 11 procurement, Step 12 HR, Step 13 full Portal and Step 14 AI/enterprise depth.

## 25. Validation rules

- Before evidence reproduces and after evidence disproves the same defect.
- All affected focused/integrated tests and critical Phase 1–4 regressions pass.
- Migration/API compatibility, exact reconciliation and scope-negative tests pass.
- Any unresolved critical/high integrity/security/financial blocker keeps task unverified.

## 26. Access rules

Use least-privilege test roles and scoped fixtures; no superuser-only acceptance. Only authorized maintainers change security/config/migrations, with reviewer evidence and separation for sensitive approvals.

## 27. Test data requirement

Reuse deterministic ATW-245 data plus minimal exploit/concurrency/failure fixtures for each finding, including Tenant A/B, customer-owner overlap, forged references, unsafe files, stale versions, duplicate jobs and external failures.

## 28. Tests to create/update

- One targeted regression per finding.
- Adversarial RLS/RBAC/field/file/job/realtime/integration tests.
- Ledger/event/idempotency/concurrency/migration/recovery tests.
- Rerun full transport and critical WMS E2E plus target-volume profiles.

## 29. Regression tests

All ATW-221..245 suites and impacted Phase 1–4 gates. Compare same checkpoint/profile before/after; no unrelated test deletion, snapshot relaxation or permission broadening.

## 30. Commands to run

Run repository lint/typecheck/test/build, security/dependency/static checks, migrations, policy matrix, file/integration failure, concurrency/reconciliation, target-volume and browser/accessibility E2Es. Record exact commands and never suppress a failure.

## 31. Documentation to update

Finding root cause/change/evidence/closure, security/integrity architecture, threat model, runbooks, known issues/risks, schema/API/data-flow and ATW-246 log. Keep RPD-022 and phase boundaries explicit.

## 32. Rollback/recovery note

Each repair has a reversible code/config/data plan; preserve accepted events and audit, reconcile ledger/jobs/Finance, restore last trusted behavior and rerun invalidated gates. No destructive Git/database shortcuts.

## 33. Acceptance criteria

- Every blocking ATW-245 finding is repaired and independently reproducible as fixed.
- Isolation, integrity, financial compatibility and recovery gates pass.
- Full critical E2Es and performance budgets do not regress.
- Residual risks are explicit, owned and non-blocking.

## 34. Definition of Done

All scoped findings have minimal reviewed fixes, failing-then-passing regressions, migration/contract/docs/rollback evidence and rerun integration gates; no critical tenant/security/inventory/financial blocker remains.

## 35. Completion report format

Report IDs/checkpoints; finding→root cause→change→test→result table; files/migrations/contracts; commands; adversarial/integrity/performance evidence; residual risks; docs; rollback/resume; ATW-247 recommendation. Update ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release ATW-247 after ATW-246 is `VERIFIED`. Do not set `PHASE_5_VERIFIED`; only Prompt 248 may do so.
