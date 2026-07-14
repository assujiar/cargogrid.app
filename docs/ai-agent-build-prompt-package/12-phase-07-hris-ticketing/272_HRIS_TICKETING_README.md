# Phase 7 — HRIS and Ticketing Prompt Package

**Document ID:** `CG-AABPP-HRT-272`  
**Version:** `0.13.0`  
**Status:** `FINAL_FOR_STEP`

## 1. Purpose

This directory builds workforce management and service control on the verified Platform, Operations, Finance and Procurement foundations. Package completion is not runtime implementation.

It covers all 20 minimum master-prompt capabilities and all 40 anchors in `HRS-EMP-001..004`, `HRS-REC-001..004`, `HRS-ATT-001..004`, `HRS-PAY-001..004`, `HRS-KPI-001..004`, `HRS-ESS-001..004`, `TKT-INT-001..004`, `TKT-CUS-001..004`, `TKT-HLP-001..004` and `TKT-SLA-001..004`.

## 2. Runtime entry gate

Prompt 273 must stop with `PHASE_7_BLOCKED` unless the same active checkpoint proves:

- `RUNTIME_DISCOVERY_VERIFIED`;
- `RUNTIME_ARCHITECTURE_VERIFIED`;
- `PHASE_0_VERIFIED` through `PHASE_6_VERIFIED`.

The kickoff must reconcile repository/branch/HEAD/worktree ownership; schema/migrations; Platform identity, organization, position, approval, workflow, files, notifications, jobs and API primitives; operational fleet/driver/assignment identities; Finance posting and payment boundaries; vendor/customer/shipment/invoice/warehouse roots; ticket-link design; environment; baselines; and unresolved ledgers before any Phase 7 task becomes `READY`.

## 3. Required hierarchy and atomicity

Prompt 273 creates repository-specific workstreams, epics, capabilities, feature slices and atomic tasks. Prompts 274–296 are capability envelopes that must be instantiated as one approved atomic task with exact files, migrations, contracts, tests, evidence and rollback boundaries.

No task may combine unrelated employee identity, recruitment, time, payroll, talent, self-service, ticket channels, SLA/linkage and refactor work merely for convenience.

## 4. Capability catalogue and dependency order

| Order | Prompt | Capability | Primary anchor |
|---:|---|---|---|
| 1 | 274 | Employee master | HRS-EMP-001..004 |
| 2 | 275 | Organization and position linkage | HRS-EMP-001..004 |
| 3 | 276 | Recruitment, job portal and ATS | HRS-REC-001..004 |
| 4 | 277 | Onboarding and offboarding | HRS-REC/ESS-001..004 |
| 5 | 278 | Attendance | HRS-ATT-001..004 |
| 6 | 279 | Shift, roster and scheduling | HRS-ATT-001..004 |
| 7 | 280 | Leave, permit and business trip | HRS-ATT-001..004 |
| 8 | 281 | Overtime and timesheet | HRS-ATT-001..004 |
| 9 | 282 | Payroll foundation, benefit and reimbursement | HRS-PAY-001..004 |
| 10 | 283 | KPI and performance | HRS-KPI-001..004 |
| 11 | 284 | Training and talent | HRS-KPI-001..004 |
| 12 | 285 | ESS and MSS | HRS-ESS-001..004 |
| 13 | 286 | Internal and interdepartmental ticket | TKT-INT-001..004 |
| 14 | 287 | Customer-to-tenant ticket | TKT-CUS-001..004 |
| 15 | 288 | Tenant-to-CargoGrid helpdesk | TKT-HLP-001..004 |
| 16 | 289 | SLA and knowledge base | TKT-SLA-001..004 |
| 17 | 290 | Ticket assignment | all TKT families |
| 18 | 291 | Ticket escalation | TKT-SLA and channel families |
| 19 | 292 | Typed ticket-linked records | all TKT families |
| 20 | 293 | Sensitive personal and payroll data controls | all HRS families; NFR-SEC |
| 21 | 294 | Integrated verification | all Phase 7 capabilities |
| 22 | 295 | HR/ticket integrity, privacy and service hardening | evidence-ranked blocker repair |
| 23 | 296 | Documentation and handoff | Phase 8/9 contracts |
| 24 | 297 | Independent closure | `PHASE_7_VERIFIED` gate |

## 5. Binding employee, organization and lifecycle rules

- Reuse Platform user, company, branch, department, team, position and role foundations. Employee is a workforce/domain profile linked to identity; it is not a duplicate authentication user or organization tree.
- Employee records retain tenant/company/branch, employee number, employment type/status, position/grade, manager/reporting line, effective-dated assignments, work contact, sensitive personal profile, documents and source/config versions.
- Recruitment covers vacancy, candidate, assessment, interview, offer and governed conversion. Candidate identity and documents remain purpose-bound; only an accepted, approved onboarding flow may create/link an employee and user account.
- Onboarding/offboarding uses versioned checklists, approvals, asset/access/task handoffs and effective dates. Offboarding must revoke or schedule access through Platform identity controls without deleting required HR, Finance, Operations or audit history.
- Operations driver/fleet assignments reference the employee/workforce identity when applicable; HRIS must not create a second driver, vehicle, vendor or shipment identity.
- Every active critical record retains its applied configuration version under RPD-040. Effective-dated corrections preserve history and do not silently rewrite prior payroll, time or performance evidence.

## 6. Binding time, payroll and talent rules

- Attendance, shift, roster, leave, permit, business trip, overtime and timesheet use exact timezone, workday, schedule, location-policy, exception, approval and correction lineage. RPD-004 keeps the runtime responsive and online-first; no offline synchronization is implied.
- Time requests and corrections are employee/manager/HR scoped, idempotent and auditable. Approved time evidence may feed payroll but never silently mutates finalized payroll.
- Payroll is an Indonesia-first configurable foundation, not an assertion of current statutory correctness. RPD-016 requires dated HR/payroll/Finance/legal SME evidence before affected rules are activated.
- Payroll calculations use exact decimals, versioned components/formulas, periods, earning/deduction/benefit/reimbursement/tax/loan inputs, approvals, snapshots and reconciliation. Payslips are private, signed, audited files.
- HRIS may emit approved payroll posting/payment inputs. Finance remains owner of journals, periods, bank/cash, settlement and reconciliation; HRIS never edits posted journals or creates a duplicate Finance ledger.
- KPI, performance, training and talent criteria, weights, cycles, calibration, outcomes and manual adjustments are versioned and explainable. Decisions remain human-governed; predictive scoring and autonomous recommendations remain Step 14.
- ESS/MSS exposes only own/team/purpose-permitted data and actions. Manager scope follows effective organization/reporting relationships, never a client-supplied employee ID.

## 7. Binding ticket-channel, SLA and linkage rules

- One canonical ticket model supports internal/interdepartmental, customer-to-tenant and tenant-to-CargoGrid helpdesk channels while preserving distinct principal, tenant, customer and support boundaries.
- Internal employees are Layer 3 tenant users. Customer users are Layer 4 and may see only permitted company/account/site records. CargoGrid support access is case-, purpose- and time-bound under Platform support controls; no fifth access layer is created.
- Ticket lifecycle, category, priority, channel, queue, requester, assignee, watchers, conversation, private/internal note, attachment, SLA clocks, assignment, escalation and resolution are canonical and versioned.
- Assignment uses eligible queue/team/user scope, availability and workload without duplicating employee, user, vendor or customer identity. Automated routing is rule-based and explainable; AI triage remains Step 14.
- SLA calendars, pause/resume rules, target versions, breach events and escalation paths are deterministic, auditable and replay-safe. Knowledge articles have audience, version, review, publication and expiry controls.
- Ticket links use a typed reference table with validation to canonical shipment, invoice, warehouse, vendor, customer and user records. A link grants no access by itself; every read, search, notification, export and attachment operation rechecks both ticket and linked-record authorization.
- Full Customer Portal account management, dashboard and complaint experience remains Step 13. Phase 7 supplies the customer-ticket domain/API contract and only the minimum bounded channel surface needed to verify isolation.

## 8. Binding privacy, files and cross-cutting controls

- Personal, candidate, attendance, payroll, bank/tax and performance data are classified, minimized, purpose-bound, field-masked and access-audited. Generic search, logs, cache, notifications, reports and exports must not leak restricted fields.
- Every upload is private and malware-scanned before release under RPD-032. Signed URLs are short-lived and scope-bound; download/access, quarantine, replacement, retention and legal hold are auditable.
- MFA is required for privileged roles under RPD-023. Payroll publication, sensitive-master change, bulk export, support access and other high-risk actions use current authorization, reason and separation/maker-checker where configured.
- RPD-025 retention applies: finance/tax and payroll-related statutory records use the approved 10-year category where applicable; audit/security evidence 7 years; operational records contract plus 90 days; legal hold overrides deletion. Current legal classification must be verified before production activation.
- RPD-022 grants Supreme Admin absolute CRUD. Do not claim tamper-proof, immutable-for-all or non-repudiation; preserve normal-role protections, warnings, before/after evidence and explicit residual risk.
- REST and GraphQL ship from shared services with parity under RPD-033. Large imports, payroll runs, schedules, reports, notifications, SLA timers and exports use PostgreSQL durable jobs with idempotency, retry, DLQ, cancellation and reconciliation.
- High-volume employee/ticket lists use selective queries, server filtering/sort/search, cursor pagination and tenant-aware indexes. Realtime is limited to valuable ticket assignment/notification slices; no global subscriptions or browser-loaded full datasets.

## 9. Mandatory Phase 7 evidence

The runtime phase must preserve at least: canonical employee/user/org ownership; recruitment-to-onboarding conversion; time/shift/leave/overtime rules and correction; payroll source/config snapshots and Finance boundary; KPI/training/talent governance; ESS/MSS/offboarding access; three ticket-channel isolation; deterministic SLA/assignment/escalation; typed link authorization; private scanned attachments; field masking and inference protection; REST/GraphQL parity; clean build/migration/CI; target-volume employee/ticket/payroll-job evidence; and residual-risk ownership.

Critical flows include `Employee → Shift → Attendance → Exception/Correction → Approved Time → Payroll Input → Calculated/Reviewed/Finalized Payroll → Finance Handoff`, `Vacancy → Candidate → Assessment/Interview → Offer → Onboarding → Employee/User Link`, `Employee Leave Request → Manager/HR Decision → Balance/Calendar → Payroll Input`, and each ticket channel through assignment, conversation, SLA, escalation, linked-record access and closure. Delivery-plan `HRS-ATT-US-001` is mandatory.

## 10. Runtime states

`PHASE_7_NOT_STARTED`, `PHASE_7_IN_PROGRESS`, `PHASE_7_BLOCKED`, `PHASE_7_PARTIALLY_COMPLETE`, `PHASE_7_VERIFIED`, `PHASE_7_ROLLED_BACK`.

Only Prompt 297 may set `PHASE_7_VERIFIED`.

## 11. Package completion

This package is complete when files 272–297 exist, Prompts 274–296 contain all 36 mandatory fields, controls/coverage/status/manifest are updated, structural/dependency/scope validation pass, and the exact next package-generation command is `LANJUT STEP 13`.

