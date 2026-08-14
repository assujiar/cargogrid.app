# HR/Payroll Field and Record Policy Matrix

**Established by:** `CG-S12-HRT-021` (Prompt 293 — Sensitive Personal and Payroll Data Controls)
**Status:** Active — a governance/audit document over Phase 7 HR/payroll capabilities HRT-274..292's
own already-built field/record policy, plus the real fixes this checkpoint made (§3). Every control
this document names already exists in a migration cited by ID; this document adds no new database
enforcement of its own beyond §3's cited fixes. Mirrors `docs/standards/FINANCE_FIELD_POLICY_MATRIX.md`'s
exact structure (Prompt 214's own precedent), per this checkpoint's own explicit instruction.

This is the canonical HR/Payroll-domain instance of `docs/standards/DATA_CLASSIFICATION_STANDARDS.md`
§4's 8-dimension handling matrix, plus a per-surface parity audit (database, service, API, UI,
report/export, job, log, support access) — the same shape Prompt 214 established for Finance.

## 1. Sensitive HR/Payroll field groups (registry: `scripts/data-classification/registry.ts`)

Registry ids below span `HRS_REGISTRY` (personal identifiers, contact/address, emergency contact,
medical/attendance-adjacent, candidate assessment, HR-narrative reason text), `PAYROLL_REGISTRY`
(compensation/pay/reimbursement/loan figures), `PERFORMANCE_REGISTRY` (ratings/scores/rationale),
`TRAINING_REGISTRY` (training/certificate/talent-review evidence), and `TICKETING_REGISTRY`
(support-linked free text, including any HR-domain record a ticket links to via HRT-292's own
typed-link registry). All five are combined into `check-registry.ts`'s own `REGISTRY` constant.

| Registry id | Category | Level | Protected RBAC action | Tables / RPCs | Owning capability |
|---|---|---|---|---|---|
| `hrs:employees.national_id_number` | `pii` | `restricted` | `HRS:View personal data` | `app.employees`; `app.get_employee_profile` | HRT-274 |
| `hrs:employees.date_of_birth_gender` | `pii` | `confidential` | `HRS:View personal data` | `app.employees` | HRT-274 |
| `hrs:employees.personal_contact` | `pii` | `confidential` | `HRS:View personal data` | `app.employees`; `app.request_employee_change` | HRT-274 |
| `hrs:employees.personal_address` | `pii` | `confidential` | `HRS:View personal data` | `app.employees`; `app.request_employee_change` | HRT-274 |
| `hrs:employee_emergency_contacts.phone_email` | `pii` | `confidential` | `HRS:View personal data` | `app.employee_emergency_contacts` | HRT-274 |
| `hrs:employees.lifecycle_reason_narrative` **(new, HRT-293)** | `pii` | `restricted` | `HRS:View personal data` | `app.employees` (5 reason columns); `app.employee_lifecycle_events.reason`; `app.get_employee_profile`; `app.get_employee_lifecycle_history` | HRT-274, hardened HRT-293 |
| `hrs:candidates.national_id_number` | `pii` | `restricted` | `HRS:View personal data` | `app.candidates`; `app.get_candidate_profile` | HRT-276 |
| `hrs:candidates.date_of_birth` | `pii` | `confidential` | `HRS:View personal data` | `app.candidates` | HRT-276 |
| `hrs:candidates.personal_contact` | `pii` | `confidential` | `HRS:View personal data` | `app.candidates` | HRT-276 |
| `hrs:candidates.address` | `pii` | `confidential` | `HRS:View personal data` | `app.candidates` | HRT-276 |
| `hrs:candidate_assessments.score_notes` **(new, HRT-293)** | `pii` | `confidential` | `HRS:View personal data` | `app.candidate_assessments`; `app.record_assessment_result` | HRT-276, registered + audit-log-vector fixed HRT-293 |
| `hrs:interview_feedback.content` **(new, HRT-293)** | `pii` | `confidential` | `HRS:View personal data` | `app.interview_feedback` | HRT-276, registered HRT-293 |
| `hrs:job_offer_versions.compensation` **(new, HRT-293)** | `pii` | `confidential` | `HRS:View personal data` | `app.job_offer_versions` | HRT-276, registered HRT-293 |
| `hrs:attendance_events.location` | `pii` | `confidential` | `HRS:View personal data` | `app.attendance_events` | HRT-278 |
| `hrs:attendance_correction_requests.reason` | `pii` | `confidential` | `HRS:View personal data` | `app.attendance_correction_requests` | HRT-278 |
| `hrs:attendance_exceptions.waive_reason` | `pii` | `confidential` | `HRS:View personal data` | `app.attendance_exceptions` | HRT-278 |
| `hrs:schedule_assignments.cancel_reason` | `pii` | `confidential` | `HRS:View personal data` | `app.schedule_assignments` | HRT-279 |
| `hrs:schedule_swap_requests.reason` | `pii` | `confidential` | `HRS:View personal data` | `app.schedule_swap_requests` | HRT-279 |
| `hrs:leave_requests.reason` | `pii` | `confidential` | `HRS:View personal data` | `app.leave_requests` | HRT-280 |
| `hrs:leave_types.evidence_classification` | `pii` | `confidential` | `HRS:View personal data` | `app.leave_types` | HRT-280 |
| `hrs:leave_balance_ledger.reason` | `pii` | `confidential` | `HRS:View personal data` | `app.leave_balance_ledger` | HRT-280 |
| `hrs:payroll_component_versions.amounts` | `payroll` | `restricted` | `HRS:View payroll` | `app.payroll_component_versions` | HRT-282 |
| `hrs:payroll_employee_component_assignments.amounts` | `payroll` | `restricted` | `HRS:View payroll` | `app.payroll_employee_component_assignments` | HRT-282 |
| `hrs:payroll_run_employee_results.totals` | `payroll` | `restricted` | `HRS:View payroll` | `app.payroll_run_employee_results`; `app.payroll_calculation_lines`; `app.payroll_payslips` | HRT-282 |
| `hrs:payroll_reimbursement_requests.amount` | `payroll` | `restricted` | `HRS:View payroll` | `app.payroll_reimbursement_requests` | HRT-282 |
| `hrs:payroll_loans.amounts` | `payroll` | `restricted` | `HRS:View payroll` | `app.payroll_loans`; `app.payroll_loan_installments` | HRT-282 |
| `hrs:payroll_finance_handoff.payment_instructions` | `payroll` | `restricted` | `HRS:View payroll` | `app.payroll_finance_handoff_payment_instructions` | HRT-282 |
| `hrs:performance_assessment_kpi_scores.scores` | `pii` | `restricted` | `HRS:View personal data` | `app.performance_assessment_kpi_scores` | HRT-283 |
| `hrs:performance_outcomes.scores` | `pii` | `restricted` | `HRS:View personal data` | `app.performance_outcomes` | HRT-283 |
| `hrs:performance_calibration_adjustments.reasoning` | `pii` | `restricted` | `HRS:View personal data` | `app.performance_calibration_adjustments` | HRT-283 |
| `hrs:performance_appeals.reasoning` | `pii` | `restricted` | `HRS:View personal data` | `app.performance_appeals` | HRT-283 |
| `hrs:training_enrollments.participation` | `pii` | `confidential` | `HRS:View personal data` | `app.training_enrollments` | HRT-284 |
| `hrs:training_assessments.scores` | `pii` | `confidential` | `HRS:View personal data` | `app.training_assessments` | HRT-284 |
| `hrs:training_certificates.evidence` | `pii` | `restricted` | `HRS:View personal data` | `app.training_certificates` | HRT-284 |
| `hrs:training_development_plans.content` | `pii` | `restricted` | `HRS:View personal data` | `app.training_development_plans` | HRT-284 |
| `hrs:talent_review.content` | `pii` | `restricted` | `HRS:Override` | `app.talent_reviews` | HRT-284 |
| `hrs:talent_pool.membership` | `pii` | `restricted` | `HRS:Override` | `app.talent_pool_members` | HRT-284 |
| `hrs:talent_succession_candidates.evidence` | `pii` | `restricted` | `HRS:Override` | `app.talent_succession_candidates` | HRT-284 |
| `tkt:ticket_messages.body` | `support` | `restricted` | *(none — `app.can_access_ticket` row scope)* | `app.ticket_messages` | HRT-286 |
| `tkt:tickets.free_text` | `support` | `restricted` | *(none — `app.can_access_ticket` row scope)* | `app.tickets` | HRT-286 |

Support-linked HR data (a ticket's typed link to an employee/candidate/user record, HRT-292) is
governed by `app.ticket_links`' own safe-snapshot bound (three generic fields: `label`/`detail`/`status`,
never a raw row) — it never re-exposes any registry row above beyond that bound, per HRT-292's own
decision 1/2 (`docs/build-log/phase-07/HRT-292.md` §3).

Two protected HRS actions are seeded (`20260716103445_create_roles_permissions.sql`, `protected=true`):
`View payroll` and `View personal data`. Both are enforced by name across every table above and both
are fully covered by `protectedAction` registry entries — `pnpm run data-classification:check`'s own
new HRS adoption gate (§4) confirms this mechanically. `HRS:Override`, used by the three `talent_*`
rows above, is a normal (non-`protected`) workflow action in the seeded catalog — cited here as each
entry's own real authority gate, but not itself subject to the protected-action adoption sweep (mirrors
`fin:job_profitability.financial_figures`'s own `FIN:View margin` being the ONLY FIN row genuinely
`protected=true`-gated, while every other FIN entry cites a plain `FIN:View`).

## 2. 8-dimension parity audit, by surface

| Surface | State | Evidence |
|---|---|---|
| **Database** | Every sensitive read RPC performs its own explicit `self OR HRS:View-personal-data` (or `HRS:View-payroll`, or the narrower `HRS:Override` for talent) masking check, `case when v_unmasked then … else null end` — never a client-side-only hide. Column-restricted grants (`revoke select (…) … from authenticated` + explicit re-`grant`) back every one of these at the raw-table level too, so a direct Postgrest/Supabase read by `authenticated` cannot bypass the RPC's own masking — the PLT-114 pattern this whole domain inherited. **Two real gaps found and fixed this checkpoint** (Finding A): `app.employees`' five HR-narrative reason columns were unconditionally returned by `app.get_employee_profile` and included in that table's own "safe" column grant; `app.employee_lifecycle_events` carried a full unrestricted table grant with the identical reason column unmasked in `app.get_employee_lifecycle_history`. Both closed in `supabase/migrations/20260731180000_harden_hris_employee_master_sensitive_data_controls_review_fixes.sql`. | Each capability's own migration header (HRT-274/276/278/279/280/282/283/284); `20260731180000` (Finding A fix) |
| **Service (`server/`)** | Every `server/queries/*.ts`/`server/mutations/*.ts` wrapper is a thin pass-through, matching Finance's own established "RPC owns authority" convention — no query wrapper adds or removes a check the underlying RPC doesn't already enforce. | `server/queries/employee.ts`, `server/queries/payroll.ts`, and siblings, each file's own header comment |
| **API (REST/GraphQL)** | **Not applicable yet, disclosed** — identical posture to Finance (§2 of the Finance matrix). No HR/payroll capability has wired a REST/GraphQL endpoint; every page reads/writes through a Server Component/Action calling the RPC/query layer directly. `PLT-130` exists as reusable infrastructure, unused by any domain so far. | Repository-wide grep, zero `app/api/**` HR/payroll routes |
| **UI (`app/`)** | Every HR/payroll page resolves access via its own `resolve*AccessForRequest` coarse gate, then relies on the RPC's own deny/mask behavior for field-level enforcement. `app.get_employee_profile`'s server-computed `personalDataMasked` flag (never a client-side guess) drives conditional rendering in `employee-detail-panel.tsx` — confirmed this checkpoint's own fix does not change this pattern, only widens WHICH fields the same flag now correctly governs (the five reason columns). | `app/(tenant)/[tenantSlug]/hris/employees/[masterRecordId]/{page,employee-detail-panel}.tsx` |
| **Reports/export** | `app.export_employees`/`export_candidates`/`export_job_vacancies`/`export_applications` are deliberately zero-PII projections (permission-checked only, since no restricted field is ever exported) — independently confirmed by this checkpoint's own audit phase (CLEAN). **No bulk payroll export RPC exists anywhere** (`app.export_payroll*` — zero matches) — the objective's own hypothesized highest-risk surface has no live surface to exploit, disclosed rather than assumed absent. | Audit phase findings (CLEAN section); repository-wide grep for `export_payroll`/`export_employees` |
| **Job/cache** | No HR/payroll-specific background job caches a sensitive field; the notification engine is confirmed NOT integrated into HRT-274 through 285 at all (zero `register_notification_type`/`queue_notification` calls, explicitly disclosed as out-of-scope in onboarding's and training's own migration comments) — no leak surface exists because the feature isn't built. | Audit phase findings (CLEAN section) |
| **Log** | **The central gap this checkpoint fixes (Finding B).** `app.capture_audit_event`'s `p_reason` parameter is a plain TEXT column, never passed through `app.redact_audit_payload()` (which only ever redacts the jsonb `before_value`/`after_value` payloads) — every domain in this repository shares this structural gap, not only HR, but HR's own registry-classified reason columns (medical/disciplinary/personal narrative) make it the highest-severity instance. `app.query_audit_logs`/`app.export_audit_logs` are readable by ANY plain `tenant_admin` (`app.is_support_grant_authority`: Supreme Admin OR tenant_admin, zero domain permission), so this was a real cross-permission leak. **Fixed**: 37 capture_audit_event call sites across Employee Master, Leave, Recruitment/ATS, Onboarding, Attendance, Shift/Roster, and the Position-Linkage/cross-domain boundary now pass `null` for the audit-log reason argument — the same reason value already lives, exactly once, in each capability's own properly-masked domain table. A second, narrower vector (`app.record_assessment_result`'s raw `score` key in its `after_value` jsonb, which the redactor's key-name pattern does not match) is also closed. | `supabase/migrations/20260731180000` (10 sites) and `20260731190000` (27 sites) |
| **Support access** | `app.query_audit_logs`/`app.export_audit_logs` access itself is the one channel Finding B closes the HR-specific content leak on; the mechanism itself (PLT-115 `support_access_grants`, tenant-approved, time-bound) is unchanged by this checkpoint. ESS/MSS (HRT-285) was independently, adversarially tested at its own build time: payroll is structurally absent from the manager team workspace; the one real cross-role leak found there (a dual-role manager + `HRS:View personal data` holder seeing all-tenant performance outcomes) was closed with a genuine server-side re-filter, not a UI-only fix — confirmed still live-correct, unaffected by this checkpoint. | `docs/build-log/phase-07/HRT-285.md`; audit phase findings (CLEAN section, ESS/MSS) |

## 3. The gaps found and fixed this checkpoint (Findings A–D)

**Finding A (CRITICAL) — `app.employees`' five HR-narrative reason columns bypassed the personal-data
masking model entirely.** `revision_reason`/`suspend_reason`/`terminate_reason`/`archive_reason`/
`leave_reason` carry real free-text disciplinary/medical/performance narrative (populated from a
caller-supplied `p_reason`, e.g. `terminate_employee`). `app.get_employee_profile` returned all five
unconditionally (never wrapped in the `case when v_unmasked …` guard protecting every sibling
personal field); the column-restricted `grant select (…) on app.employees to authenticated` — built to
close a PRIOR raw-SELECT PII leak — itself included these five columns; `app.employee_lifecycle_events`
carried a full unrestricted grant with the identical narrative in its own `reason` column, read
unconditionally by `app.get_employee_lifecycle_history` for any plain `HRS:View` holder. **Fixed**
(`supabase/migrations/20260731180000...sql`): both tables' grants column-restricted (RLS itself left
broad and correct — an org directory's structural fields are legitimately tenant-member-visible; only
the free-text reason columns needed restricting); both read RPCs now mask to self-or-`HRS:View
personal data`, matching every sibling personal field exactly.

**Finding B (CRITICAL) — C-24 (audit-log unmasked-reason leak) was live across most of Phase 7.**
`app.capture_audit_event`'s `p_reason` argument is never redacted by `app.redact_audit_payload()`
(jsonb-payload-only); `app.query_audit_logs` is readable by any plain `tenant_admin`. Live, unfixed
sites spanned Leave, Employee Master, Recruitment/ATS, Onboarding, Attendance, and Shift/Roster — 27
sites named by the audit, plus 10 further sites this checkpoint's own live `pg_get_functiondef`
verification found were either superseded (the audit's own citation of `app.start_employee_leave`'s
pre-refactor body no longer matched its current live body, which delegates to
`app._transition_employee_leave_status` — itself carrying the real leak) or simply not individually
named by the audit's own list (`app.decide_employee_position_assignment`/`cancel_employee_position_
assignment`, `app.waive_attendance_exception`, `app.waive_onboarding_task`/`request_onboarding_access_
revocation`, `app.cancel_conflicting_schedule_assignment_for_leave`, `app.record_offer_response`,
`app.load_opening_leave_balance`) — same defect class, same capability set, found via a systematic
sweep rather than assumed complete from the audit's own line-number citations. **Fixed**
(`20260731180000`, `20260731190000`): every one of these 37 call sites now passes `null` for the
audit-log reason; the real value continues to live, exactly once, in each capability's own already
column-restricted, RPC-masked domain table.

**Finding C (HIGH) — registry gaps.** `app.candidate_assessments.score/notes`, `app.interview_
feedback.rating/recommendation/notes`, `app.job_offer_versions.compensation_amount/compensation_
currency/benefits_note` were already correctly column-restricted at the grant layer (HRT-276's own
Tier C review, `20260730870000...sql`) but carried no registry row; the Finding-A columns were
unregistered AND (unlike the above) actually unprotected. **Fixed**: five new `HRS_REGISTRY` entries
added (`scripts/data-classification/registry.ts`) — `hrs:employees.lifecycle_reason_narrative`,
`hrs:candidate_assessments.score_notes`, `hrs:interview_feedback.content`,
`hrs:job_offer_versions.compensation`. Remaining unregistered-but-touched fields (job application/
interview/onboarding-task reason columns this checkpoint's own Finding B sweep also masked from the
audit log) are disclosed, not registered, in §5 — a bounded registry-editing scope, not a claim of
exhaustive coverage.

**Finding D (HIGH) — the mechanical adoption gate never covered HRS.**
`scripts/data-classification/check-registry.ts`'s `findUnclassifiedProtectedFinActions`/
`parseSeededProtectedFinActions` were hard-coded to `'FIN'`-prefixed rows and filenames containing
`"finance"` only — no equivalent HRS sweep existed, so `pnpm run data-classification:check` could not
(and did not) catch Finding C. **Fixed**: `parseSeededProtectedHrsActions`/
`findUnclassifiedProtectedHrsActions` added, mirroring the FIN functions exactly (§4 below); a genuine,
independently self-found defect surfaced by exercising the new gate for the first time —
`PAYROLL_REGISTRY` was exported from `registry.ts` since HRT-282 but never imported into
`check-registry.ts`'s own combined `REGISTRY` constant, silently excluding it from both
`validateRegistry()` and the new adoption gate — fixed in the same edit, regression-guarded by a new
test (`check-registry.test.ts`, `PAYROLL_REGISTRY` describe block).

## 4. Adoption gate (`pnpm run data-classification:check`)

`scripts/data-classification/check-registry.ts` mechanically enforces, for HRS exactly as it already
did for FIN: every seeded `protected: true` `HRS` permission action (`View payroll`, `View personal
data`) that at least one real HRIS/payroll migration (any file whose name contains `"hris"`) actually
references by name has a matching `HRS_REGISTRY`/`PAYROLL_REGISTRY`/`PERFORMANCE_REGISTRY`/
`TRAINING_REGISTRY` entry naming it as that entry's own `protectedAction`. A future HR/payroll
capability that starts enforcing a newly-seeded protected HRS action without adding a matching registry
entry now fails this gate — closing the exact mechanism gap Finding D named, mirrored from the FIN
adoption gate `FIN-214` (Prompt 214) already established, not a new invention.

## 5. What remains out of scope, disclosed (not silently claimed complete)

- **RPD-025 retention/legal-hold classification is unbuilt for every Phase 7 HR/payroll structured-data
  table** (`ISS-2026-091`, Medium, `OPEN`) — a repository-wide grep of every HRT-274..293 migration for
  `legal_hold`/`retention_class` returns zero hits on any HR/payroll table; only the generic, reused
  `app.audit_logs`/`app.files` platform primitives carry this metadata. Directly analogous to the
  Phase 5 GPS-telemetry gap (`ISS-2026-027`), eventually fixed at `CG-S10-ATW-031` — disclosed here for
  the first time for Phase 7, not yet fixed (a genuine multi-table schema addition requiring its own
  retention-class-per-table design decision, outside this checkpoint's own Critical/High-focused bounded
  scope).
- **`app.employee_change_requests.reason`/`decided_reason` are readable by any active tenant member via
  a raw table SELECT** (`ISS-2026-092`, Medium, `OPEN`, self-found while fixing Finding A) — the
  identical shape as Finding A (a column-restricted grant that never excluded the sensitive columns,
  admitted by broad RLS), on a different table Finding A's own audit text did not name. The two
  `capture_audit_event` sites for this table ARE fixed under Finding B. The raw-table-read vector is
  not — closing it needs a genuinely new masking RPC (mirroring `app.list_employee_emergency_contacts`'s
  established convention) plus a service/UI edit, real bounded follow-up work rather than a migration-only
  fix.
- **RPD-023 (no step-up MFA on high-risk payroll actions)** — disclosed consistently since Payroll's own
  build (`docs/build-log/phase-07/HRT-282.md` decision 4) and unchanged by this checkpoint: no
  per-action step-up MFA mechanism exists anywhere in this repository yet. The compensating control
  (PLT-123 maker-checker on `finalize_payroll_run`) is real and live. Not re-verified in depth here — a
  platform-wide concern, not a per-domain one, matching the Finance matrix's own identical disclosure.
- **No REST/GraphQL surface exists for any domain yet** (§2 above) — this document cannot audit parity
  for a surface that has not been built.
- **No Customer Portal exists yet** (Step 13) — no HR/payroll field is customer-facing today; nothing to
  audit for that surface.
- **`hrs:leave_types.evidence_classification`'s own registry note already discloses** that a `'medical'`-
  classified leave type's evidence file is governed by PLT-128's own storage classification, set at
  upload time, independent of this registry's own domain-level classification — unchanged by this
  checkpoint.
- **No employee bank account/tax-ID data exists anywhere in this repository** — verified CLEAN by this
  checkpoint's own audit phase; `bank_reference_masked` on the payroll finance handoff is structurally
  always null, and the payroll build log already discloses this explicitly (`HRT-282.md` §10). Nothing to
  leak.
- **`app.cancel_approval_request` (PLT-123, the shared cross-domain approval-cancellation primitive
  every HR "cancel with reason" function calls internally) duplicates its own raw reason into
  `app.audit_logs.reason` under its own `action='cancel_approval_request'` row** (`ISS-2026-093`,
  Medium, `OPEN`, self-found while writing this checkpoint's own regression tests) — the identical
  C-24 shape as Finding B, live-confirmed, but on Platform Core infrastructure shared by every domain
  with an approval workflow (Finance, Commercial, Procurement, HR), not owned by this checkpoint's own
  Phase 7 HR/payroll mandate. Not fixed here — a dedicated Platform Core follow-up should close it once
  for every calling domain, not as a per-domain patch.
- **A handful of additional Phase 7 HR reason/narrative columns this checkpoint's own Finding B sweep
  masked from the audit log** (`app.job_applications.rejection_reason`/`withdrawal_reason`,
  `app.interviews.cancel_reason`, `app.candidate_duplicate_candidates.decided_reason`,
  `app.employee_duplicate_candidates.decided_reason`, `app.onboarding_case_tasks.waive_reason`,
  `app.employee_position_assignments.decided_reason`) remain unregistered in `scripts/data-classification/
  registry.ts`, though each is already correctly column-restricted at the grant layer and masked at its
  own owning read RPC. Bounded, disclosed registry-editing scope (§3 Finding C) — not silently claimed
  complete.
