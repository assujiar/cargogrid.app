# Prompt 282 — Payroll Foundation, Benefit and Reimbursement

**Prompt ID:** `CG-S12-HRT-010`  
**Package document:** `CG-AABPP-HRT-282`  
**Version:** `0.13.0`  
**Runtime build log:** `docs/build-log/phase-07/HRT-282.md`

Do not begin until Prompt 273 marks this task `READY`, all variables are resolved, and `PHASE_6_VERIFIED` matches the active checkpoint.

## 1. Prompt ID

`{{TASK_ID}}` mapped to `CG-S12-HRT-010` and exactly one approved WBS/task-ledger item.

## 2. Parent phase

`Phase 7 — HRIS and Ticketing`; package `0.13.0`.

## 3. Workstream

Workstream: Payroll, Benefit and Reimbursement; Epic: Controlled Payroll Calculation; Capability: Payroll Component, Run, Payslip, Benefit and Reimbursement; Feature slice: repository-specific bounded slice; Atomic task: `{{WBS_TASK_ID}}`.

## 4. Objective

Implement an Indonesia-first configurable payroll foundation with exact versioned calculations, governed finalization, private payslips and reconciled Finance handoffs.

## 5. Business value

Calculate workforce obligations consistently without leaking compensation data or duplicating Finance journal, payment and reconciliation truth.

## 6. Source requirement

HRS-PAY-001..004 and HRIS Payroll, Benefit & Reimbursement requirement card. Cite exact source sections, runtime evidence, decisions/config versions and prerequisite task IDs.

## 7. Current repository context

Record repository root, branch, HEAD, dirty-worktree ownership, active closures, schemas/migrations/contracts/routes/modules/jobs/integrations, package manager/scripts, environment, baseline and last trusted checkpoint.

## 8. Preconditions

Read persistent context/status/task/change/decision/assumption/error/issues/handoff artifacts, Phase 6 closure, relevant build logs and sources. Inspect actual code/schema/policies/APIs/UI/jobs/files/tests, run feasible baselines, state plan/files, and stop on tenant/identity/privacy/payroll/Finance/ticket/data/phase-boundary conflict.

## 9. Upstream dependencies

HRT-274..281; verified Finance configuration/posting/period/payment contracts and Platform approval/file/job primitives. Every execution-index prerequisite must be `VERIFIED`.

## 10. Downstream impact

HRT-283..297. Identify affected schemas, services, REST/GraphQL, jobs/integrations/files, HR/manager/employee/customer/support/Finance/Operations consumers, tests, docs and compatibility contracts.

## 11. Allowed files/folders

Use only exact Phase 7 schema, migration, service, UI, job/integration, test and documentation paths authorized by WBS. Resolve repository paths; normally 5–15 files and at most 1–3 additive migrations.

## 12. Forbidden files/folders

Unrelated domains, duplicate identity/organization/employee/Finance/ticket roots, full Step 13–14 implementation, tenant forks, applied-migration edits, destructive cleanup, hidden test/permission weakening and user-owned unrelated changes.

## 13. Database impact

Create payroll calendar/period, component/formula/version, employee component assignment, input snapshot, run/batch, calculation line, earning/deduction/benefit/tax/loan/reimbursement, review/exception, finalization, payslip and Finance-handoff records using exact decimals. No duplicate GL, AP, bank or settlement ledger.

## 14. API impact

Shared REST/GraphQL configuration, input preview/freeze, calculate/recalculate draft, review/approve/finalize, correction, payslip, benefit/reimbursement request/approval and source-reconciled Finance handoff APIs; heavy runs are durable jobs. REST and GraphQL share authentication, authorization, field policy, idempotency, audit and version semantics.

## 15. UI/UX impact

Restricted payroll configuration/run workspace, source/input reconciliation, employee calculation detail, exception/review/approval, reimbursement queue and private employee payslip/benefit views with field masking and safe totals. Include keyboard/focus/labels, unsaved-change protection and no dead action.

## 16. Security impact

Salary, allowance, deduction, tax, bank, loan, benefit, reimbursement and payslip are highest-sensitivity HR/payroll fields; require explicit purpose/field policy, privileged MFA/re-auth where configured, maker-checker, export controls, private scanned files and enhanced audit. Preserve tenant/company/branch/department/employee/customer/record/field/file scope, RLS/RBAC, server-only secrets, private scanned files and RPD-022 residual-risk disclosure.

## 17. Performance impact

Index tenant/company/payroll period/run/employee/component/status; batch/chunk payroll jobs with checkpoint, retry, cancellation, DLQ and reconciliation; server-side aggregates and no row-level realtime. Use selective columns, server filter/sort/search, cursor pagination, async heavy work and measured evidence; no `SELECT *`, global realtime or browser-loaded full dataset.

## 18. Audit impact

Record component/formula/config/source versions, input freeze, calculation lines/totals, manual adjustment, review/approval/finalize/correction, payslip generation/access/export and Finance handoff/acknowledgement. Include actor/context, source/config versions, correlation/idempotency, before/after or event chain, outcome and privileged-access evidence.

## 19. Data migration impact

Load opening employee components, balances/loans and year-to-date values only through signed source/control totals and SME-approved mapping; preserve prior run evidence and never fabricate statutory calculations. Use additive or expand-and-contract migrations; never edit applied migrations. Rehearse backup, rollback and source/downstream reconciliation.

## 20. Detailed implementation tasks

- Prove HR payroll versus Finance journal/payment ownership and exact handoff contract.
- Define exact component/formula/input/run/finalize/correction and reconciliation invariants.
- Implement schema/policies/services/APIs, durable jobs and restricted accessible UX.
- Implement benefit/reimbursement/loan inputs, private payslips and Finance handoff.
- Run dated Indonesia payroll/Finance/legal SME validation and security/scale/recovery tests.

## 21. Main flow

Payroll freezes approved employee/time/benefit/reimbursement inputs for a period and config version, runs exact draft calculations, resolves exceptions, obtains maker-checker approval, finalizes a snapshot, publishes private payslips and emits acknowledged Finance posting/payment inputs.

## 22. Alternative flow

Off-cycle run, retroactive correction, adjustment, reimbursement-only cycle, component change, loan installment, failed batch resume or statutory configuration held inactive pending SME evidence.

## 23. Exception flow

Block missing/duplicated input, invalid formula/version, imbalance with source totals, unauthorized sensitive access, stale approval, finalized-period mutation, failed file scan or unacknowledged Finance handoff; preserve resumable run checkpoint. Record blocker/error/issue, owner and exact safe resume; never hide or bypass failure.

## 24. Business rules

- All money/rates/units use exact decimals and explicit rounding; no binary-float authority.
- Input, formula, component, tax/statutory and organization versions are frozen per run; finalized history never silently recalculates.
- RPD-016 requires current dated HR/payroll/Finance/legal SME evidence before statutory rules are enabled; prompts do not assert legal correctness.
- HR payroll calculates and approves workforce obligations; Finance alone owns journals, period lock, bank/cash, payment, settlement and reconciliation.
- Finalized correction creates a linked governed adjustment/off-cycle version; RPD-022 residual admin risk remains explicit.

## 25. Validation rules

Validate employee/payroll eligibility, period, approved source inputs, exact units/currency/rounding, component/formula dependency graph, config/SME activation, separation/approval, reconciliation totals, file state and Finance contract before finalization.

## 26. Access rules

Payroll roles operate runs; separate authorized approvers finalize; employees read own published payslips/benefits; managers cannot see compensation by hierarchy alone; Finance receives only contracted approved data. Policies cover queries, exports, jobs, files and logs. Enforce authorization in database/service as applicable, not UI only; list/search/export/report/realtime use the same policy.

## 27. Test data requirement

Salaried/hourly/contract employees, join/exit/transfer, paid/unpaid time, benefits/loans/reimbursements, retro/off-cycle, formula cycle/error, rounding edges, failed/resumed batch, sensitive roles and Tenant A/B fixtures. Include deterministic IDs, allowed/denied roles, retries/concurrency and source/config versions.

## 28. Tests to create/update

- Exact component/formula/run/finalize/correction domain tests.
- Input freeze/source-total/Finance-handoff reconciliation tests.
- RLS/RBAC/field-mask/MFA-maker-checker/export/log/file negative tests.
- Durable payroll job retry/cancel/DLQ/recovery/load tests.
- Payslip/reimbursement restricted browser/accessibility E2E and dated SME UAT evidence.
- Unit/component/integration/API contract/database/migration/audit/smoke coverage proportional to risk.

## 29. Regression tests

Employee/time/leave/overtime inputs, Finance posting/period/payment/reconciliation, Platform approval/files/jobs/notifications and generic search/export/logging. Re-run tenant/field/file isolation, browser/accessibility and critical Phase 1–6 compatibility suites; compare baseline before/after.

## 30. Commands to run

Detect and run repository equivalents of lint, typecheck, unit/integration/database/API/contract/browser/accessibility/security and build; add relevant migration/type generation, job/import/load/failure-recovery/reconciliation commands. Do not disable a gate; register proven pre-existing failures.

## 31. Documentation to update

Payroll ownership and Finance handoff, component/formula/version, period/run/finalization/correction, Indonesia SME activation, benefit/reimbursement/loan, payslip privacy and disaster/reconciliation runbooks. Update persistent context/status/task/change/error/issue/traceability/schema/API/data-flow/dependency/build-log artifacts.

## 32. Rollback/recovery note

Stop new runs/handoffs, preserve frozen/finalized snapshots and Finance acknowledgements, cancel/resume batch safely, revert compatible code/config for future runs and reconcile source/payroll/Finance totals before reopening. State last trusted checkpoint, reversible steps, reconciliation and exact resume; no destructive Git/database shortcuts.

## 33. Acceptance criteria

- Exact versioned payroll foundation calculates and finalizes from reconciled approved inputs.
- No duplicate Finance ledger/payment truth is introduced; handoff is acknowledged and reconcilable.
- RPD-016 SME gate, maker-checker/MFA, masking, files and payslip privacy pass.
- Batch retry/cancel/recovery, correction and Tenant A/B performance gates pass.
- Mandatory automated/manual gates pass at one recorded checkpoint with source requirement → code/contract/UI → test → documentation evidence.

## 34. Definition of Done

Scope is implemented without placeholder/fake persistence/dead action; migrations, generated types, RLS/RBAC/field policy, shared APIs, complete UX states, jobs/integrations, tests, docs, audit, performance evidence and rollback are complete; no critical tenant/identity/privacy/payroll/Finance/ticket blocker remains.

## 35. Completion report format

Report task/prompt IDs; repository checkpoint; changed files/migrations/contracts; source/config decisions; implementation; commands and baseline/after results; tenant/identity/access/privacy/payroll/Finance/ticket evidence; idempotency/concurrency/reconciliation/performance; residual errors/issues/risks; docs; rollback/resume; recommended next task. Update persistent ledgers before `VERIFIED`.

## 36. Next eligible prompt

Only the execution index may release HRT-283 or another dependency-clean task after this task is `VERIFIED`. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

