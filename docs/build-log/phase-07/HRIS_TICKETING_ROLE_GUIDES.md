# Phase 7 (HRIS and Ticketing) Role Guides

**Produced by:** `CG-S12-HRT-024` (Prompt 296 — HRIS and Ticketing Documentation and Handoff), per Prompt 296 §20's own "publish employee/manager/HR/payroll/recruiter/service/support role guides" deliverable.

**Companion document:** `docs/build-log/phase-07/HRIS_TICKETING_RUNBOOKS.md` — scenario-based diagnosis/resolution for when something has already gone wrong. This document answers a different question: for a given role, what can they see and do, through which real route/action, and what does a given error actually mean.

**How to use this document:** each section below names the real, live, `VERIFIED` UI route and the real RPC/permission action behind it — never an aspirational or planned surface. Every capability cited is drawn directly from its owning build log (`docs/build-log/phase-07/HRT-274.md` through `HRT-295.md`). Where a role's access is narrower than it might look, that narrowing is stated explicitly, since several of these guides describe deliberate, disclosed boundaries (e.g. what a manager can never see) that are easy to mistake for a bug from the outside.

**Sanitization:** every example below (`Jane Doe`, `EMP-0001`, round figures, synthetic tenant codes) is fictional and deterministic. No raw payroll, PII, ticket content, token, or private URL appears anywhere in this document.

---

## 1. Employee — Employee Self-Service (ESS)

**Entry point:** `app/(tenant)/[tenantSlug]/hris/my` — the ESS home (`HRT-285`), a server-rendered landing page with six cards (attendance/schedule, leave/overtime, payslip/benefit, performance, training, profile), each a bounded count plus a link to that capability's own detail page. No write action lives on the home page itself.

**What this role can see/do:** every self-service action resolves the acting employee through `app.get_self_employee`/identity-match — **no `HRS` permission is required for any of it**, by design. An ordinary employee with zero role assignments can do everything below.

| Task | Real route | Real action |
|---|---|---|
| View/edit own profile, request a change | `hris/my/profile` | `app.get_my_employee_profile` (always unmasked for self, regardless of `HRS` permission); `app.request_employee_change` |
| Clock in/out, view recent days, request a correction | `hris/my/attendance` | `app.record_attendance_clock_event` (self-only — carries no employee-id parameter to spoof), `app.request_attendance_correction` |
| View published schedule, request a swap | `hris/my/schedule` | `app.list_schedule_assignments` (self-scoped), `app.request_schedule_swap` |
| View leave balance, create/submit/cancel a leave/permit/business-trip request | `hris/my/leave` | `app.get_employee_leave_balance`, `app.create_leave_request`/`submit_leave_request`/`cancel_leave_request` |
| Create/submit overtime requests and timesheet entries, submit own period summary | `hris/my/overtime-timesheet` | `app.create_overtime_request`, `app.create_timesheet_entry`, `app.submit_timesheet_period_summary` |
| View own payslips (line-item detail), own reimbursement requests, own loans (read-only) | `hris/my/payroll` | `app.list_my_payslips`, `app.list_my_payroll_reimbursement_requests`, `app.list_my_payroll_loans` — all gated `self OR HRS:View payroll`, never manager-of-employee |
| Own goals/self-assessment, own outcomes, acknowledge, appeal | `hris/my/kpi-performance` | `app.submit_performance_self_assessment`, `app.acknowledge_performance_outcome`, `app.submit_performance_appeal` |
| Browse/enroll in training, manage own enrollments, own certificates, own development plan, own assigned talent-review cases (if a reviewer) | `hris/my/training-talent` | `app.enroll_self_in_training_session`, `app.cancel_training_enrollment`/`app.reschedule_training_enrollment`, `app.submit_talent_review` (only if genuinely assigned as a reviewer) |
| File and reply to internal tickets | `tickets`, `tickets/[ticketId]` | `app.create_ticket`, `app.reply_to_ticket` (public visibility only — an ordinary employee is never staff on their own filed ticket unless separately a queue member) |

**Common errors and what they mean:**
- `insufficient_authority` on any self-service RPC almost always means the caller-supplied identity does not match the session — this repository's own self-service RPCs resolve the actor server-side and reject a mismatched claim outright.
- `employee_not_active` — attempting to clock in while `lifecycle_status` is not `active`/`on_leave` (e.g. suspended or terminated). This is a real, independent check Attendance performs itself, distinct from Platform-authority revocation.
- `duplicate_workday_session` — a second clock-in attempt for a day that already has a session.
- `leave_request_overlap` — the requested dates conflict with an already-`pending_approval`/`approved` request for the same employee; a `draft` request may freely overlap another draft, the real conflict is only enforced at submit time.
- A masked field showing blank/null on **someone else's** profile is expected (visible only to self or an `HRS:View personal data` holder); the same field is always visible, unmasked, on the employee's own profile regardless of any `HRS` permission.

---

## 2. Manager — Manager Self-Service (MSS), effective-team scope

**Entry point:** `app/(tenant)/[tenantSlug]/hris/team` — the MSS team workspace (`HRT-285`), a pure composition layer over the SAME already-authority-checked RPCs every capability above already exposes. **Zero new table, zero new RPC** — manager status alone grants nothing; every read/write below is the identical RPC an HR/payroll staffer would call, scoped a second time to the caller's own direct reports.

**Scope: "effective team" is direct reports only** — a single-level `manager_employee_id` match (`app.list_my_team_employees`, reused verbatim, never a recursive org-tree walk). A manager sees exactly their own direct reports, never a skip-level report, and never an unrelated colleague.

| Section | What it shows | Real composition |
|---|---|---|
| Team roster | Direct reports (bounded to 50 rows, with a truncation indicator if exceeded — `ISS-2026-084`, disclosed, Low) | `app.list_my_team_employees` |
| Unified approvals queue | Pending leave/overtime/timesheet/training decisions for direct reports ONLY | Routes through `app.decideLeaveRequest`/`decideOvertimeRequest`/`decideTimesheetEntry`/`decideTrainingEnrollment` unchanged, via one pure router (`decideManagerApprovalQueueItem`) that performs zero authority check of its own — every real check is the owning capability's own |
| Team schedule | Next 14 days for direct reports | `app.list_schedule_assignments`, manager-scoped |
| Team performance summary | Current cycle goals/outcomes for direct reports | `app.list_performance_goal_assignments`/`list_performance_outcomes`, re-filtered a SECOND time in the TS layer against the caller's own team-id set — this second filter is load-bearing, not decorative (see below) |
| Team training status | Team-scoped enrollments/certificates | `app.list_training_enrollments`/`list_training_certificates` |

**Deliberately, structurally excluded from MSS — do not treat as a bug:**
- **Attendance-correction and schedule-swap decisions do not appear in the approvals queue.** Both `app.list_attendance_correction_requests`/`app.list_schedule_swap_requests` gate on plain `HRS:View` ONLY — neither has a manager-of-employee scope branch at all. Composing them would either render permanently empty or require inventing new scope logic outside any one capability's own chartered mandate. A manager needing to act on either must be separately granted `HRS:View`/`HRS:Edit`.
- **Payroll is entirely absent.** `getMssTeamWorkspace` never imports from the payroll query layer at all — there is no code path by which a team member's compensation could reach this page, regardless of what other permissions a manager might separately hold.
- **Talent review/pool/succession is entirely absent**, and independently hard-rejected at the RPC layer even if it were called — talent visibility is `HRS:Override`-only, never self, never direct manager (a second, independent line of defense beyond the UI simply not calling it).
- **A dual-role manager who ALSO happens to hold a broader `HRS` permission (e.g. `HRS:View personal data`) still sees only their own genuine direct reports on this page** — every MSS list is intersected a second time, defensively, in the TS composition layer against the caller's own real team-id set. This was proven load-bearing, not redundant, by a live reproduction at build time: without this second filter, a dual-role manager+HR actor calling the underlying RPC directly with no employee filter would see EVERY employee's performance outcome in the tenant, not just their own two direct reports'.

**Common errors and what they mean:**
- An empty roster/queue renders `EmptyState: "No direct reports"` rather than a redirect — a genuine non-manager visiting this page is not an error, just an empty state.
- `self_approval_not_permitted`/`self_calibration_not_permitted` — a manager attempting to decide their own item even though they separately hold the deciding permission; structurally blocked everywhere, no exceptions.

---

## 3. HR/Payroll staff — the two-tier permission distinction, concretely

This is the single most commonly misunderstood permission shape in Phase 7. There are **two separate, protected `HRS` actions**, and holding one does **not** imply the other:

- **`HRS:View`** — the plain, module-scoped baseline. Sees non-sensitive structural fields across HRIS (lists, statuses, counts) but **not** masked personal or payroll content. Notably, `HRS:View` alone is NOT even enough to see `app.payroll_periods`/`app.payroll_components`/`app.payroll_component_versions` — those three tables are RLS-gated on `HRS:View payroll` specifically, deliberately stronger than plain tenant membership, because even a period's own existence/status can disclose whether/when a compensation cycle ran.
- **`HRS:View personal data`** — the general "see an individual's sensitive personal content" gate across almost every other HRIS capability: national ID, date of birth, personal contact/address, emergency-contact phone/email, candidate PII, attendance location, leave reason/destination, lifecycle/termination reason narrative, performance scores and rationale, calibration/appeal reasoning, training participation/assessment scores/certificate evidence, and development-plan content. (This single permission action is also, deliberately, reused for the KPI/Performance domain's own masking — `app.permissions.action` is a closed, fixed catalogue, and adding a bespoke `HRS:View performance` action was considered and rejected at `HRT-283` build time; every reference to "performance visibility" in this repository is really `HRS:View personal data`.)
- **`HRS:View payroll`** — a genuinely SEPARATE, narrower permission for compensation data specifically: `payroll_component_versions`/`payroll_employee_component_assignments`, `payroll_run_employee_results`/`payroll_calculation_lines`/`payroll_payslips`, reimbursement requests, loans, and the Finance-handoff payment instructions. **Deliberately not inherited from `HRS:View personal data`, and deliberately not inherited from being someone's direct manager** — a manager holding `HRS:View personal data` (even a direct manager) sees ZERO of a report's payroll data unless they ALSO, separately, hold `HRS:View payroll`.
- **`HRS:Override`** — the highest bar, reserved for the highest-blast-radius actions: employee terminate/suspend/rehire-reactivate; attendance exception waive; a schedule-assignment change to an already-PUBLISHED row; the leave coverage-threshold bypass and the explicit schedule-override cancel; KPI calibration and appeal decisions; the ENTIRE talent-review/pool/succession domain (both read and write — deliberately narrower than `HRS:View personal data`, never self, never direct manager); and, since `HRT-295`, granting any Platform role/access through the onboarding access-provisioning RPC (tightened from `HRS:Edit` after a real, live privilege-escalation finding — see below).
- **A concrete example of the split in practice:** an "HR Generalist" role might reasonably hold `HRS:Create`/`Edit`/`View`/`View personal data` (can create/edit employee records, see personal fields, review leave reasons) but hold **no** `HRS:View payroll` — such a person genuinely cannot see a single payslip figure, by design. A "Payroll Officer" role would hold `HRS:View payroll` plus whatever Payroll-domain actions (`Create`/`Edit`/`Approve`) their job needs, and might or might not also hold the broader `View personal data`.

**Common tasks, with real routes:**

| Domain | Route | Notes |
|---|---|---|
| Employee lifecycle | `hris/employees`, `hris/employees/[masterRecordId]` | draft→submitted→approved→active; suspend/terminate/archive/reactivate; `rehire_employee` (terminated→active only); the "Restore Platform access (rehire)" action wires `app.reactivate_user_after_rehire` (a real, governed, separately-callable Platform-identity step, distinct from the HR-record-level rehire) |
| Organization/position | `hris/positions`, `hris/organization`, `hris/employees/[masterRecordId]/positions` | governed propose/decide assignment workflow; a free-text transfer is REJECTED (`governed_position_exists`) once an employee has a real governed position — use the assignment wizard instead |
| Recruitment | `hris/recruitment` and children | see the Recruiter guide below |
| Onboarding/offboarding | `hris/onboarding`, `hris/onboarding/templates` | checklist-driven case workflow; access provisioning now requires `HRS:Override` for an actual role grant (not merely `HRS:Edit`) since `HRT-295`'s privilege-escalation fix |
| Attendance | `hris/attendance`, `hris/attendance/policies` | sessions table, exceptions queue (waive requires `HRS:Override`), corrections queue (decide requires `HRS:Approve`), payroll-input approval trigger |
| Shift/Roster | `hris/shifts`, `hris/roster`, `hris/roster/cycles` | template/version authoring, manual assign, batch generation from a rotating cycle, coverage preview, swap-request decide |
| Leave | `hris/leave`, `hris/leave/types` | decide (approve/reject, coverage-override), manual balance adjustment, employee-status resync |
| Overtime/Timesheet | `hris/overtime-timesheet`, `.../policies` | decide overtime/timesheet, period create/lock/reopen, summary approve/reject/reopen, payroll-input handoff generate |
| Payroll | `hris/payroll` | periods (create/freeze/reopen), components (create/assign), loans, reimbursements (decide), runs (create/calculate/submit-for-finalization/finalize-or-reject/cancel — **finalize requires a DIFFERENT eligible approver**, self-approval structurally blocked), exceptions (resolve/waive), Finance handoff (generate/acknowledge — acknowledge requires `FIN:Edit` specifically, the ONE cross-module gate in this whole capability, never any `HRS` action) |
| KPI/Performance | `hris/kpi-performance` | KPI library, templates, cycles, goal/reviewer assignment, reviewer reassignment (never silently transfers an already-submitted review), calibration (`HRS:Override`), appeal decision (`HRS:Approve`) |
| Training/Talent | `hris/training-talent` | full authoring, plus the restricted talent workspace (`HRS:Override` gate on both read AND write — a plain `HRS:Edit`/`Approve` holder gets zero rows on talent pool/succession tables, not merely a denied write) |

**Common errors and what they mean:**
- `insufficient_authority` — most often the wrong permission TIER, not a missing permission entirely (e.g. holding `HRS:View personal data` but attempting a payroll action that needs `HRS:View payroll`).
- `approval_self_approval_denied`/`self_approval_not_permitted` — a maker-checker block; the requester and the decider are the same identity even though that identity also separately holds the deciding permission.
- `governed_position_exists` — attempting the old free-text transfer/update on an employee who already has a governed position assignment.
- `target_identity_not_activatable` — attempting to grant Platform access to a user not currently `active`/`invited`. If this is a genuine rehire, use the employee detail page's "Restore Platform access (rehire)" action first (`HRT-295`), which correctly reactivates a `revoked` identity tied to a real, on-file rehire event — this does NOT happen automatically when the HR record is rehired; it is a separate, explicit, `HRS:Override`-gated action.
- `org_unit_inactive` — attempting to assign into a deactivated company/branch/department.
- `stale_version` — someone else edited the record first; re-fetch and retry with the current version.
- `employee_number_conflict` — an explicit employee number collided with an existing one.

---

## 4. Recruiter — candidate/offer pipeline, the public intake surface

**Entry points:**
- `hris/recruitment` — vacancy list + create-draft.
- `hris/recruitment/[vacancyId]` — vacancy detail, pipeline table, status transitions, add-candidate.
- `hris/recruitment/applications/[applicationId]` — candidate profile, stage transitions/history, assessment CRUD, interview scheduling + feedback, offer create/submit/decide/extend/response.
- `hris/recruitment/my-interviews` — interviewer self-service (identity-gated; only the assigned interviewer may submit feedback for their own assigned interview).
- `app/(public)/careers/[tenantSlug]` and `app/(public)/careers/[tenantSlug]/[postingToken]` — the genuinely public, anonymous, token-based intake surface. Enumeration-safe (a bad slug, a bad/expired token, and a closed vacancy all produce the identical uniform response) and rate-limited (10 failed attempts per client key within a rolling window). **Resume upload is deliberately NOT on the public form** — a candidate's resume is attached post-intake, staff-mediated, via a governed re-attach RPC re-validating malware-scan status; this is a deliberate risk-reduction choice, not a missing feature.

**Permissions:** `HRS:Create`/`Edit`/`Approve`/`Reject`/`Export`/`View`/`View personal data` — candidate PII (national ID, date of birth, personal contact, address) is column-restricted from the very first migration and masked to self-or-`HRS:View personal data` exactly like employee PII.

**Offer approval routes through the shared PLT-123 Approval Engine** — no bespoke threshold table. Note: this same `config_type_code='approval'` singleton is shared tenant-wide across Sales quotation, credit control, Procurement PO, and job-offer approval (`ISS-2026-069`, disclosed, Medium, `OPEN`) — a tenant that publishes an approval-routing definition for one of these domains is affecting the shared singleton, not a job-offer-specific one; check with whoever owns approval-routing configuration before assuming a job-offer approval failure is Recruitment-specific.

**The recruitment→onboarding conversion:** once an offer reaches `offer_accepted`, this checkpoint deliberately stops — **no employee/user row is ever created by Recruitment itself** (an explicit, tested boundary). HR completes the conversion via Onboarding (`app.start_onboarding_case`, source `job_offer`). Since `HRT-295`, a `job_offer`-sourced conversion correctly consumes real position headcount and creates a real, governed position assignment (closing a prior, real over-hire gap, `ISS-2026-107`, `RESOLVED` for this path). The `direct_hire` onboarding path still has **no position input at all** — a disclosed, narrower, still-open gap distinct from the resolved `job_offer` path.

**Common errors and what they mean:**
- `vacancy_headcount_exceeds_position_capacity` — the vacancy's requested headcount would exceed the linked position's real remaining capacity.
- `idempotency_key_conflict` — a resubmitted create call with the same key but different content.
- `offer_approval_no_longer_applicable` — a concurrent reject/withdraw raced the pending approval decision; re-check the application's current stage before retrying.
- `evidence_file_infected`/`evidence_file_not_scanned` — the resume-attach malware-scan gate; re-checked both at attach time AND again at the interview-stage transition, never trusted from a prior success.
- **Hiring managers have no self-scoped "assigned slice" read surface today** (`ISS-2026-068`, disclosed, Medium, `OPEN`) — unlike interviewers (who have `my-interviews`), a hiring manager currently needs broader `HRS:View` to see their own vacancy's pipeline; there is no narrower, hiring-manager-scoped equivalent yet.
- Duplicate-candidate search/flag/decide, and the export RPCs, are real and tested but have no UI caller yet (`ISS-2026-067`, disclosed, Low) — reachable via a direct call if genuinely needed.

---

## 5. Service/Support agent — the three ticket channels, escalation, SLA

**The three channels, and what an ordinary tenant-side agent works:**

1. **Internal** (`HRT-286`) — `tickets`, `tickets/[ticketId]`. Employee-to-employee/department tickets. Requester/assignee/watcher/queue-staff identity all resolve through `app.employees`.
2. **Customer-to-Tenant** (`HRT-287`) — an agent works these through the SAME internal `tickets` queue view (channel badge distinguishes them); the customer's own side is a separate, bounded surface at `customer-tickets`/`customer-tickets/[ticketId]`, structurally excluded from any internal RPC/route. A customer's requester identity is an **account**, not a person — any active member of the same account sees the account's own tickets, not merely the literal creator.
3. **Helpdesk (Tenant-to-CargoGrid)** (`HRT-288`) — a tenant files a Platform support case at `helpdesk`/`helpdesk/[ticketId]`, authorized via a real `tenant_admin` membership OR a real tenant-scoped `TKT:Edit` grant (deliberately employee-independent — works even before any HR onboarding exists for the filer). The Platform side of THIS channel is Supreme-Admin-only staff (see the Platform Support guide below) — a tenant-side agent never sees the Platform-internal triage view for their own helpdesk case.

**Common tasks (internal + customer channel):**

| Task | Real action |
|---|---|
| Reply publicly / post an internal note | `app.reply_to_ticket` (`visibility='public'`/`'internal'` — structurally distinct; a customer requester can never post `internal` through any path) |
| Claim a ticket (self) | `app.claim_ticket` — workload-cap hard-blocked, no override |
| Assign a ticket (as a manager) | `app.assign_ticket` — workload cap overridable with an explicit reason (`p_override_workload_limit`); eligibility (active employee, not on an approved leave day) is a hard block with NO override on either path |
| Accept/decline own assignment | `app.accept_ticket_assignment`/`app.decline_ticket_assignment` |
| Transfer queue / reclassify | `app.transfer_ticket_queue`/`app.update_ticket_classification` |
| Transition status (resolve/close/reopen/cancel) | `app.transition_ticket_status` — a fixed, validated graph |
| Watch / stop watching | `app.add_ticket_watcher`/`app.remove_ticket_watcher` |
| Redact a message | `app.redact_ticket_message` (`TKT:Edit`) |
| Search/link/unlink a typed record | `app.search_ticket_link_candidates`/`app.link_ticket_record`/`app.unlink_ticket_record` — mandatory reason on link |
| Acknowledge / manually escalate / suppress an escalation | `app.acknowledge_ticket_escalation`, `app.escalate_ticket` (mandatory reason), `app.suppress_ticket_escalation` (`TKT:Assign`, mandatory reason + expiry) |
| View/manage SLA calendars and policies | `tickets/sla` (`TKT:Edit`) |
| Author/review/publish a knowledge-base article | `knowledge-base`, `knowledge-base/[articleId]` — self-review structurally blocked at both submit and decide time |
| Browse the breach/stuck-ticket queue | `tickets/breach-queue` |
| Author routing rules, preview scope | `tickets/routing` |

**Permission model:** plain queue membership is sufficient for ordinary ticket work — reading internal notes, replying, transferring, reclassifying — with no extra named permission needed beyond being requester/assignee/watcher/queue member. `TKT:Assign`/`Close`/`Reopen`/`Edit` gate the higher-stakes actions specifically. `TKT:Edit` is a genuine, disclosed design tension worth knowing about (`ISS-2026-086`, Medium, `OPEN`): it grants BLANKET, tenant-wide, non-queue-scoped ticket-staff status (needed by `redact_ticket_message` and by post-transfer scenarios), even though the capability's own header comment frames it as "reserved for configuration." This is not a bug awaiting a fix — it is a deliberate, disclosed tension between two legitimate needs of the same permission.

**Common errors and what they mean:**
- `ticket_not_found` covers BOTH "does not exist" and "exists, but you may not see it" — by design, anti-enumeration. Do not read it as proof a ticket doesn't exist.
- `invalid_transition` — an illegal status jump, OR an action attempted against a `closed`/`cancelled` ticket. Since `HRT-295`, linking a new record or adding a watcher on a closed/cancelled ticket correctly raises this; UNLINKING a record or REMOVING a watcher remains permitted on a closed/cancelled ticket (a deliberate asymmetry — winding down an existing engagement is treated differently from starting a new one).
- `channel_not_supported` — attempting an internal-shaped RPC (`assign_ticket`, `transfer_ticket_queue`, etc.) against a helpdesk ticket. Helpdesk has its own dedicated, Supreme-Admin-gated siblings (`assign_helpdesk_ticket`, etc.) — never use the generic RPC against it.
- `workload_limit_exceeded` — a self-claim at capacity, with no override available; ask a manager to `assign_ticket` with an explicit override + reason instead.
- `employee_not_eligible` — the target is suspended/terminated, or on an approved leave day covering today; unconditional, no override on any path.
- `record_not_eligible` on a linked-record attempt — see runbook 5 in the companion runbooks document for the full six-domain diagnosis.
- `escalation_already_suppressed`/`escalation_target_not_eligible` — an active suppression already exists on this ticket, or the manual-escalation target is missing/ineligible.

---

## 6. Platform Support — the helpdesk channel, Supreme-Admin-only escalation model, PLT-115 case-bound access

**Entry points:** `app/(supreme)/supreme/helpdesk` (a genuinely cross-tenant queue — no `p_tenant_id` required, sees every tenant's helpdesk cases in one view) and `app/(supreme)/supreme/helpdesk/[ticketId]` (the triage panel: reply public/internal, assign, transfer support queue, reclassify, transition, and correlate a support-access-grant case reference).

**The defining, deliberate constraint of this role:** staff status on a helpdesk-channel ticket is **Supreme-Admin-authority only** (`app.is_ticket_staff` hardened specifically for `channel='helpdesk'`, `HRT-288` decision B) — there is currently no dedicated, non-Supreme-Admin "Platform support agent" identity anywhere in this repository. `app.support_queues` (the Platform-side triage catalogue) is a genuinely parallel, Platform-wide table with no `tenant_id`/`org_unit_id` at all — CargoGrid support is never modeled as an org unit of any tenant.

**A helpdesk ticket's requester is the TENANT ITSELF**, never a specific employee or account — authorized via a real `tenant_admin` membership or a real tenant-scoped `TKT:Edit` grant, resolved through a helper (`app._is_tenant_helpdesk_authorized`) that deliberately bypasses `app.evaluate_permission`'s own RPD-022 Supreme-Admin shortcut, so a Supreme Admin can never accidentally count as "the tenant side" of a case they hold no genuine membership in.

**Common tasks:**

| Task | Real action | Note |
|---|---|---|
| Triage the cross-tenant queue | `app.list_platform_helpdesk_tickets` | Supreme Admin only; a tenant admin gets zero rows |
| Assign / transfer / reclassify a helpdesk ticket | `app.assign_helpdesk_ticket`/`app.transfer_helpdesk_support_queue`/`app.update_helpdesk_ticket_classification` | dedicated Supreme-Admin-gated siblings — the generic `assign_ticket`/`transfer_ticket_queue`/`update_ticket_classification` explicitly reject a helpdesk ticket outright |
| Reply publicly or with an internal Platform note | `app.reply_to_ticket` (direct) or `app.reply_to_helpdesk_ticket` (tenant-side entry point, public only) | a tenant's own `TKT:Edit` holder can NEVER post an internal note here, by design |
| Redact a message | `app.redact_ticket_message` | Platform-staff-only for a helpdesk ticket — a tenant's own `TKT:Edit` holder cannot redact even a PUBLIC message on their own helpdesk ticket, since a naive redaction authority would otherwise let them destroy Platform-internal diagnostic content they cannot even read |
| Correlate a support-access-grant case reference | `app.link_helpdesk_support_grant` | display/audit only — validates a REAL `app.support_access_grants` row exists for `(tenant_id, case_id)`; never itself grants/extends/revokes anything |

**The correlation-not-access-grant guarantee, stated once more because it is the single most security-sensitive property of this role:** holding an active, approved PLT-115 support-access grant confers **zero** ticket-staff/access status on the correlated helpdesk ticket, and being staff on a helpdesk ticket confers **zero** tenant business-data access — both directions independently, repeatedly live-proven. Actual tenant business-data access is granted **exclusively** by the unmodified PLT-115 flow (`app.request_support_access`/`approve_support_access`/`start_support_session`/`revoke_support_access`) — see runbook 4 in the companion runbooks document for the full diagnostic path if this ever seems to be behaving otherwise.

**Common errors and what they mean:**
- `channel_not_supported` — using a generic internal-ticket RPC against a helpdesk ticket instead of its dedicated Platform-side sibling.
- `insufficient_authority` — either a tenant admin attempting a Platform-only action, or (rarer, and worth escalating immediately if seen) a Supreme Admin attempting to act as a tenant's own requester without a genuine membership.
- `support_grant_not_found` — a forged or genuinely nonexistent case reference supplied to the correlation RPC.
- `assignee_not_support_staff` — attempting to assign a helpdesk ticket to an identity that does not hold Supreme Admin authority.
- `invalid_severity` — an out-of-enum severity value on classification.

**Disclosed, still-`OPEN` limitations for this role:** no dedicated, non-Supreme-Admin "Platform support agent" role exists (a deliberate, bounded-scope decision, not an oversight); no attachment-upload UI for the helpdesk surface yet (the RPC-level malware-scan gate is real, just not exercised by a dedicated upload widget); the Platform helpdesk queue page itself has no server-side filter UI wired in yet, though the underlying query layer supports status/severity/product-area filtering fully.
