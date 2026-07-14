# Prompt 297 — HRIS and Ticketing Closure Verification

**Prompt ID:** `CG-S12-HRT-025`  
**Package document:** `CG-AABPP-HRT-297`  
**Version:** `0.13.0`  
**Runtime output:** `docs/build-log/phase-07/HRIS_TICKETING_CLOSURE_REPORT.md`

Do not begin until Prompt 296 is `VERIFIED`, the active checkpoint still carries `PHASE_6_VERIFIED`, and all Phase 7 capability, integrated-verification, hardening and handoff evidence is available for independent review.

## Objective

Independently verify Phase 7 HRIS and Ticketing runtime completeness, workforce/payroll integrity, personal-data privacy, ticket-channel isolation and Finance/Operations/Platform compatibility before Phase 8 Customer Portal and Loyalty implementation.

## Required verification

1. Verify Prompts 273–296 at one repository/schema/environment checkpoint and reconcile every WBS, dependency, traceability and evidence link.
2. Confirm all 20 master capabilities have implementation, migration/contract/UI as applicable, tests, documentation and owner: employee master; organization/position linkage; recruitment; onboarding/offboarding; attendance; shift; leave; overtime; payroll foundation; KPI/performance; training; employee self-service; internal ticket; customer ticket; CargoGrid support ticket; SLA; assignment; escalation; linked shipment/invoice/warehouse/vendor/customer/user; sensitive personal/payroll controls.
3. Confirm all 40 anchors across `HRS-EMP-001..004`, `HRS-REC-001..004`, `HRS-ATT-001..004`, `HRS-PAY-001..004`, `HRS-KPI-001..004`, `HRS-ESS-001..004`, `TKT-INT-001..004`, `TKT-CUS-001..004`, `TKT-HLP-001..004` and `TKT-SLA-001..004` map to durable runtime evidence with no orphan.
4. Prove Platform user/authentication and company/branch/department/team organization roots remain authoritative while HRIS adds one canonical workforce employee profile, effective position/grade/manager assignments and no duplicate user or organization truth.
5. Prove employee number, employment type/status, personal/work profiles, documents, lifecycle, transfer/promotion/suspension/termination/archive and reporting-line changes are tenant-aware, effective-dated, acyclic, versioned and auditable.
6. Prove existing Operations driver/workforce/assignment references adopt canonical employee links where applicable without creating duplicate driver, vehicle, vendor, shipment or warehouse identity.
7. Prove `Vacancy → Candidate → Consent/Application → Assessment/Interview → Approved Offer → Acceptance → Onboarding → Employee/User Link` is idempotent and candidate identity/PII/files never silently become employee or Platform user truth.
8. Prove onboarding/offboarding uses versioned checklists, dependency/owner/due/evidence, acknowledged access/asset/training/payroll/Operations handoffs, emergency exit and rehire/cancel handling. Access revocation goes through Platform authority and required history remains.
9. Prove `Employee → Published Shift/Policy → Online Clock-In/Out → Exception/Correction → Approved Time → Payroll Input` including Delivery `HRS-ATT-US-001`, server-authoritative time, source-versus-approved evidence, timezone/workday/cross-midnight and no offline-sync claim.
10. Prove shift/roster templates, segments, breaks, timezone, calendars, coverage, overlap, swap/override and employee assignments are versioned/effective-dated; downstream attendance/leave/overtime retain the applied published snapshot.
11. Prove leave/permit/business-trip policies, eligibility, accrual/expiry/carry-forward, exact units, balance ledger, schedule/holiday/overlap/coverage, approval/cancellation/correction and payroll/calendar impacts reconcile. No silent balance mutation is allowed.
12. Prove overtime/timesheet requested, actual, eligible, approved and paid inputs remain distinct; exact interval/rounding/cap/break rules, attendance/leave/work-reference checks, period lock/reopen and one idempotent payroll input pass.
13. Prove the payroll foundation covers exact versioned earning, allowance, deduction, benefit, reimbursement, tax, loan and payslip behavior; employee/time/source/config/formula/component inputs freeze per run and finalized corrections use linked governed versions.
14. Prove RPD-016 current dated Indonesia HR/payroll/Finance/legal SME evidence gates statutory activation. Reject guessed compliance and every claim that static prompt text proves current legal correctness.
15. Prove payroll batch chunk/checkpoint/retry/cancel/DLQ/resume/reconciliation, input/source totals, review, maker-checker approval, finalization, private payslip publication and correction/off-cycle recovery pass at declared target volume.
16. Prove Finance remains owner of journals, period lock, bank/cash, payment, settlement and reconciliation. HR payroll emits approved source-linked handoffs only, never creates a duplicate Finance ledger or silently edits posted/finalized Finance records.
17. Prove KPI/performance definitions, weights, units, targets, cycles, assessments, exact scoring, calibration/manual adjustments, outcomes, acknowledgement and appeal are versioned, explainable, field-restricted and human-governed.
18. Prove training/talent covers catalogue/session, prerequisite/capacity, enrollment, completion, assessment, certificate/expiry, development plan and restricted talent review with private scanned evidence; no autonomous/predictive talent decision.
19. Prove ESS/MSS is a policy-safe projection/action surface over canonical services, not a second HR datastore. Own/effective-team scope, manager transfer/revocation, module entitlement, sensitive widget/count/search/cache/notification/export inference and canonical writes pass.
20. Prove one canonical ticket/channel/message model supports internal/interdepartmental, customer-to-tenant and tenant-to-CargoGrid helpdesk without duplicate ticket roots or a fifth principal/access layer.
21. Prove internal requester/queue/department/participant/watcher access, customer-visible reply versus internal note, ordered idempotent messages, lifecycle, reopen and private scanned attachments for `TKT-INT-001..004`.
22. Prove Layer 4 customer membership—not payload—sets account/company/site scope; customer ticket list/thread/search/count/file/link projections cannot leak other customers, internal notes, tenant/support fields or existence. Full portal UX remains Step 13.
23. Prove tenant-to-CargoGrid helpdesk keeps tenant and Platform support principals separate; a ticket alone grants no tenant business-data access and any privileged support/impersonation session is case-, purpose- and time-bound, MFA-protected, bannered and audited.
24. Prove deterministic SLA policy selection, target and business-calendar versions, response/resolution clock ledger, pause/resume/reopen/correction, reminder/breach idempotency, retry/replay/reconciliation and dashboard source accuracy across all channels.
25. Prove knowledge articles require version, audience, reviewer, publish and expiry/review lifecycle; draft/internal/support content never leaks to customer search, snippets, cache, ticket links or exports.
26. Prove ticket routing/assignment uses canonical user/employee/team/queue identities, server-side eligibility/availability/delegation/workload, atomic claim/reassign, revocation, explainable versioned rules and safe notification/realtime fallback.
27. Prove escalation trigger/policy/level/target/action is uniquely keyed, idempotent, acknowledged and retry/DLQ/cooldown/suppression controlled; repeated failures cannot produce notification storms or customer-visible internal metadata.
28. Prove typed ticket links validate canonical shipment, invoice, warehouse, vendor, customer and user records through a registry/domain adapter. A link grants no access; search, summary, deep link, cache, notification and export reauthorize both ticket and source record.
29. Prove Platform owns identity/access/config/files/jobs/audit; Operations owns shipment/warehouse execution; Procurement owns vendor governance; Finance owns posting/payment; Ticketing stores no duplicate source truth and only minimum safe linked context.
30. Prove personal, candidate, attendance/location, compensation, bank/tax, loan/reimbursement, performance/talent and support-linked HR fields have a complete purpose/role/field/record matrix enforced across database, service, REST/GraphQL, UI, jobs, files, logs, cache, search, notification, reports and exports.
31. Prove managers do not gain payroll, bank/tax, medical, candidate, talent or unrestricted personal data through hierarchy alone; small-cohort aggregates, counts, saved filters, errors, URLs and logs resist inference.
32. Prove RPD-032 every upload is private and malware-scanned before release; quarantine, short-lived scope-bound signed URLs, replacement/version, access/download audit, retention and legal hold work for HR and ticket files.
33. Prove RPD-023 MFA/current authorization for privileged roles and configured high-risk payroll publication, sensitive-master change, export and support access; maker-checker/separation failures are denied and audited.
34. Prove RPD-025 approved retention categories and legal hold are applied with dated legal classification where needed, while data minimization and employee/candidate lifecycle do not erase required Finance/payroll/audit history.
35. Prove RPD-033 REST/GraphQL parity and identical field/record/file/job/idempotency/audit/version behavior; forged references, retries, concurrency and revocation have equivalent outcomes.
36. Prove RPD-040 active employee/time/payroll/performance/SLA critical records retain applied configuration/source versions; configuration changes do not silently rewrite historical calculations or decisions.
37. Confirm RPD-022 permits Supreme Admin absolute CRUD over employee, payroll, ticket, SLA, link and audit records. Verify normal-role safeguards and warnings/evidence, but reject tamper-proof, immutable-for-all or non-repudiation claims.
38. Prove RPD-004 responsive online-first PWA, WCAG/browser/loading/empty/error/denied/conflict/degraded states and no fake success/dead action for employee, manager, HR/payroll, customer and support surfaces.
39. Prove target-volume employee/search/import, attendance, roster/leave/overtime, payroll batch/payslip, ESS/MSS, ticket list/thread/search/dashboard, SLA/assignment/escalation jobs, notification and export meet declared query/job/backpressure budgets with privacy/integrity parity.
40. Confirm full Customer Portal account/dashboard/self-service and Loyalty remain Step 13; AI triage/summarization, predictive workforce/talent, autonomous recommendation and enterprise depth remain Step 14. Phase 7 did not smuggle later scope.
41. Confirm clean install and Phase 6→7 upgrade, generated types, CI, backup/restore, import/opening-balance reconciliation, observability/runbooks and zero unresolved critical/high tenant, identity, personal/payroll, Finance, customer/support, ticket, file, integration, performance or evidence blocker.
42. Confirm no production, external-pilot, partial-GA or market-ready claim. RPD-001/034/036 still require every major module and full internal validation before direct GA.

## Closure states

- `PHASE_7_VERIFIED`: every mandatory HRIS/Ticketing runtime gate passes.
- `PHASE_7_PARTIALLY_COMPLETE`: bounded non-critical evidence remains; Phase 8 is blocked.
- `PHASE_7_BLOCKED`: a critical tenant/identity/privacy/payroll/Finance/customer/support/ticket/file/link/integration/schema/contract/evidence gate fails.
- `PHASE_7_ROLLED_BACK`: the phase returned to a trusted checkpoint and must resume.

## Required output

Write artifact/task/capability/requirement checklist; checkpoint/schema/API/UI/access matrix; 20-capability × 40-anchor evidence map; canonical employee/user/org/Operations ownership proof; recruitment/onboarding/offboarding; time/shift/leave/overtime; payroll exactness, SME activation and Finance handoff; KPI/training/talent; ESS/MSS; three ticket channels; SLA/knowledge/assignment/escalation; typed links and source-domain authorization; personal/payroll classification and inference matrix; files/MFA/retention/audit; REST/GraphQL/jobs/performance; migration/recovery; later-phase boundary audit; RPD-022/statutory residual-risk disclosure; residual issues; closure state/rationale; Phase 8 eligibility; and exact resume/next prompt.

## Completion gate

Set `PHASE_7_VERIFIED` only if every mandatory runtime check passes. This is not production, market, pilot or GA status. For package generation, the exact next command after Step 12 validation is `LANJUT STEP 13`.

