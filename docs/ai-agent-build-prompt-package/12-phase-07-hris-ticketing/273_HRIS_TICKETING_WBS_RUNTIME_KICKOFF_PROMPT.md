# Prompt 273 — HRIS and Ticketing WBS Runtime Kickoff

**Prompt ID:** `CG-S12-HRT-001`  
**Package document:** `CG-AABPP-HRT-273`  
**Version:** `0.13.0`  
**Runtime output:** `docs/build-log/phase-07/00_EXECUTION_INDEX.md`

## Objective

At one authoritative repository, schema and environment checkpoint, decompose Phase 7 into dependency-clean atomic tasks and release only tasks whose prerequisites are verified. Do not implement a capability in this kickoff.

## Mandatory entry gate

Stop and write `PHASE_7_BLOCKED` unless the same checkpoint proves `RUNTIME_DISCOVERY_VERIFIED`, `RUNTIME_ARCHITECTURE_VERIFIED`, `PHASE_0_VERIFIED`, `PHASE_1_VERIFIED`, `PHASE_2_VERIFIED`, `PHASE_3_VERIFIED`, `PHASE_4_VERIFIED`, `PHASE_5_VERIFIED` and `PHASE_6_VERIFIED`.

Read `CARGOGRID_CONTEXT.md`, `CARGOGRID_BUILD_STATUS.md`, `TASK_LEDGER.md`, `CHANGE_MANIFEST.md`, `DECISION_REGISTER.md`, `ASSUMPTION_REGISTER.md`, `ERROR_LEDGER.md`, `KNOWN_ISSUES.md`, current handoff, discovery/architecture closure, Phase 0–6 closure reports and relevant source requirements. Inspect actual schemas, migrations, RLS/RBAC, services, REST/GraphQL, UI, jobs, files, notifications, tests and scripts. Record repository root, branch, HEAD, dirty-worktree ownership, environment, schema/config versions, supported commands, baselines and last trusted checkpoint.

## Required ownership reconciliation

Before creating tasks, prove or block on:

1. Platform identity versus HR employee profile ownership; tenant/company/branch/department/team/position/reporting-line scope.
2. Effective-dated employment, organization, position and manager links without duplicating Platform organization truth.
3. Candidate/recruitment identity, document and user-account conversion ownership.
4. Operations fleet/driver/vendor/assignment identities versus workforce references.
5. Finance ownership of journal, period, bank/cash, payment, settlement and reconciliation versus HR payroll calculation and approved handoff.
6. Canonical customer, shipment, invoice, warehouse, vendor and user records for typed ticket links.
7. Four principal/access layers for employee, customer and CargoGrid support sessions; no vendor/customer/support collision.
8. Shared workflow/approval/status/numbering, configuration version, notification, file scan/signed URL, audit, import/export and PostgreSQL job primitives.
9. Current dated Indonesia payroll/statutory SME activation evidence under RPD-016.
10. RPD-022/023/025/032/033/040 contracts and unresolved critical/high issues.

If ownership is ambiguous, create a blocking ADR task before any affected implementation. Do not resolve ambiguity by creating duplicate roots.

## Required hierarchy and task contract

Create Phase → workstream → epic → capability → feature slice → atomic task → verification → hardening → documentation → closure records. Every atomic task must contain:

- unique WBS/task/prompt IDs and one owner;
- exact source anchors and user/acceptance evidence;
- exact prerequisite task IDs and downstream consumers;
- exact allowed/forbidden paths;
- normally 5–15 changed files and at most 1–3 additive migrations;
- schema/API/UI/security/performance/audit/migration impacts;
- test data, automated/manual gates and repository commands;
- checkpoint, rollback, reconciliation and exact resume;
- runtime log path under `docs/build-log/phase-07/`.

Split a capability prompt into smaller atomic tasks when file, migration, risk, approval or independent-test boundaries require it. Never combine unrelated HR, payroll and ticket work into one task.

## Required workstreams

At minimum create workstreams for:

- Workforce Master and Lifecycle;
- Recruitment and Workforce Entry/Exit;
- Time, Attendance and Scheduling;
- Payroll, Benefit and Reimbursement;
- Performance, Learning and Talent;
- Employee and Manager Self-Service;
- Ticket Channels and Conversation;
- SLA, Assignment, Escalation and Knowledge;
- HR/Ticket Privacy, Files, API and Jobs;
- Integrated Verification, Hardening, Documentation and Closure.

## Required capability and anchor mapping

Map each of the 20 capability prompts 274–293 to at least one atomic task and map all 40 anchors across six HRS and four TKT families. No anchor may be orphaned and no task may claim an anchor without implementation/test/documentation evidence.

Preserve these boundaries:

- full Customer Portal/Loyalty UX and account management stays Step 13;
- AI triage, predictive workforce analytics, autonomous recommendation and enterprise depth stay Step 14;
- Finance owns posting/payment/period/reconciliation;
- Operations owns shipment/warehouse execution and resource custody;
- Procurement owns vendor governance;
- Platform owns identity/access/config/files/jobs/audit;
- HRIS/Ticketing extends those contracts without duplicate truth.

## Execution-index rules

Mark a task `READY` only when every prerequisite is `VERIFIED`, exact paths and commands are resolved, baseline is recorded, no critical ownership/security/privacy/payroll/Finance/ticket-link conflict exists, and rollback/recovery is feasible.

Only the execution index may release the next task. Independent tasks may run concurrently only when their file, migration, contract, data and evidence surfaces do not overlap. Conflicting work remains serialized.

Use only `NOT_STARTED`, `READY`, `IN_PROGRESS`, `BLOCKED`, `FAILED`, `PARTIALLY_COMPLETE`, `COMPLETED`, `VERIFIED`, `ROLLED_BACK`, `SUPERSEDED`.

## Mandatory quality gates

Define repository-specific gates for:

- clean install and Phase 6→7 upgrade;
- generated types, lint, typecheck, unit/integration/database/API/contract/browser/accessibility/build;
- tenant/company/branch/department/employee/customer/support and field-level isolation;
- employee/org/recruitment/time/payroll/performance/ESS lifecycle and effective-date concurrency;
- ticket channel, requester/watcher/assignee/internal-note/file/link isolation;
- exact payroll decimals, component/formula/config snapshots, correction/finalization and Finance handoff reconciliation;
- deterministic timezone/workday/shift/leave/overtime calculations;
- SLA clock/pause/calendar/version, assignment/escalation retry and notification idempotency;
- upload malware scan, quarantine, signed URL and access log;
- import/payroll/report/SLA job retry, cancellation, DLQ and reconciliation;
- target-volume employee, attendance, payroll run, ticket list/thread/dashboard and export performance;
- RPD-022 residual-risk disclosure and later-phase scope audit.

## Required output

Write an execution index containing checkpoint; runtime entry verdict; ownership/ADR map; workstream/epic/capability/slice/task hierarchy; dependency graph; 20-capability × 40-anchor traceability; file/migration/contract collision matrix; baseline/gate matrix; critical path; owner; task state; evidence/log path; rollback; resume; and first eligible prompt.

If every entry gate passes, set `PHASE_7_IN_PROGRESS` and release only dependency-clean tasks. Do not set `PHASE_7_VERIFIED`; only Prompt 297 may do so.

