-- HRIS capability HRT-282 (Prompt 282, CG-S12-HRT-010) -- Payroll Foundation,
-- Benefit and Reimbursement. Ninth Phase 7 capability, built directly on
-- HRT-274 (Employee Master), HRT-278 (Attendance), HRT-280 (Leave), HRT-281
-- (Overtime/Timesheet), and reusing PLT-123 (Approval Engine) and PLT-131/132
-- (the durable job framework) without inventing a second copy of either.
--
-- This is run as its OWN single-prompt Tier C batch -- the single most
-- sensitive and highest-scope capability in Phase 7 so far (mandatory
-- reading item 0 of the runtime instructions this checkpoint was built
-- under). Every decision below is disclosed, not silently assumed.
--
-- ===========================================================================
-- DECISION 1 -- HR Payroll vs Finance ownership, the exact handoff contract
-- (Prompt 282 section 20 task 1 / section 111, mandatory reading item 6).
-- ===========================================================================
--
-- Read in full before writing this migration: FINANCE_HANDOFF_PACKAGE.md
-- sections 2.1/3, and the real code of
-- app.prepare_finance_vendor_bill_from_actual_cost (20260729140000) and
-- app.search_finance_ap_candidates_for_settlement (20260729150000). The
-- shape those two establish: a capability that owns a governed source
-- record hands Finance an APPROVED, VERSIONED intake input through a
-- `prepare_finance_*_from_*`-named function; Finance's own domain table is
-- populated only from that prepared, reconciled input, never re-typed; the
-- SOURCE domain never inserts into a Finance-owned ledger/journal/payment/
-- settlement table directly.
--
-- Applied here, in the SAME direction Prompt 282's own section 111 demands
-- ("Payroll NEVER writes to app.journal_entries, app.finance_settlements,
-- app.finance_payments, or any Finance-owned ledger table directly -- zero
-- GRANT, zero INSERT/UPDATE on any of those from this migration"):
--
-- * Payroll owns its OWN full lifecycle end to end -- calendar/period,
--   component/formula/version, employee assignment, input snapshot, run/
--   batch, calculation line, review/exception, maker-checker finalization,
--   and private payslip. Every one of those tables/functions lives in THIS
--   migration, under app.payroll_*, and only Payroll writes to them.
-- * The handoff artifact Payroll hands to Finance is `app.payroll_finance_
--   handoff_batches`/`_gl_lines`/`_payment_instructions` -- a NEW table
--   family, still owned by Payroll (this checkpoint's own migration 2,
--   `20260731010000_bind_hris_payroll_to_finance_handoff.sql`), generated
--   by `app.prepare_finance_payroll_disbursement_handoff_from_payroll_run`
--   (the exact `prepare_finance_*_from_*` naming shape) from a FINALIZED
--   run only. This mirrors `app.prepare_finance_vendor_bill_from_actual_
--   cost` precisely: a source-domain function that turns an approved,
--   immutable upstream record into a structured intake package -- except
--   here Payroll is BOTH the source domain and the current owner of the
--   intake table, because no Finance-side capability to consume a payroll
--   disbursement exists yet anywhere in this repository (disclosed, not
--   invented) -- there is no Prompt 200-equivalent Finance capability for
--   payroll to hand into. `app.search_payroll_finance_handoffs_pending_
--   acknowledgement` mirrors `app.search_finance_ap_candidates_for_
--   settlement`'s own "how the OTHER domain discovers candidates prepared
--   by this one" shape exactly, gated on `FIN:View` -- so a genuinely
--   Finance-authorized actor, or a future Finance capability built on top
--   of this exact function, can find what Payroll has prepared without
--   Payroll ever reaching into a Finance table.
-- * `app.acknowledge_payroll_finance_handoff_batch` (migration 2) is
--   deliberately gated on `FIN:Edit`, not any `HRS:*` action -- the ONE
--   place this migration requires the calling actor to hold Finance
--   authority, proving the acknowledging actor is genuinely Finance-side,
--   never merely a Payroll actor self-certifying receipt. This is the
--   concrete, enforced shape of "Finance receives only contracted approved
--   data" (Prompt 282 section 26) and of "handoff is acknowledged and
--   reconcilable" (section 33).
-- * Zero `GRANT`/`INSERT`/`UPDATE`/`SELECT`-write on any `app.finance_*`
--   table anywhere in either of this checkpoint's two migrations --
--   grep-verified, recorded in the build log (`docs/build-log/phase-07/
--   HRT-282.md` section on this exact decision).
--
-- ===========================================================================
-- DECISION 2 -- ISS-2026-074 resolution (mandatory reading item 7): which of
-- app.attendance_sessions (HRT-278) vs app.payroll_time_inputs (HRT-281) is
-- canonical for regular payroll time, and how double-counting is prevented.
-- ===========================================================================
--
-- Both HRT-278 and HRT-281 independently, and incompatibly, called
-- themselves "the forward contract Prompt 282 is expected to consume."
-- Direct code read (HRT-281's own migration, current post-review-fix
-- schema, mandatory reading item 8) confirms `app.payroll_time_inputs.
-- regular_minutes`/`overtime_*_minutes` are populated EXCLUSIVELY from
-- `app.timesheet_entries` rows reachable via `source_entry_ids` -- an
-- employee who only ever clocks in/out via Attendance and never touches
-- Timesheet contributes ZERO regular minutes to that table, even though
-- `app.attendance_sessions.payroll_input_status='approved'` rows exist and
-- are real, governed, HR-approved evidence (`app.approve_attendance_for_
-- payroll_input`, HRT-278).
--
-- This checkpoint's resolution (documented per-employee-per-work-date, not
-- merely "prefer one table over the other" at the whole-period grain, since
-- that would either double-count or silently drop real approved time):
--
-- `app._resolve_payroll_time_inputs_for_period` reads BOTH sources for one
-- (tenant, employee, period_start, period_end) and applies an explicit
-- work-date-level precedence rule:
--   1. Every `app.payroll_time_inputs` row with `status='active'` whose
--      OWN `app.timesheet_periods` window falls inside the payroll period's
--      date range contributes its `regular_minutes`/`overtime_*_minutes`
--      AS-IS (its own totals are already the timesheet-entries-derived,
--      approved figure -- authoritative for every work_date reachable via
--      its `source_entry_ids`).
--   2. For every OTHER work_date inside the payroll period's range NOT
--      reachable via step 1's `source_entry_ids` (resolved by joining
--      `app.timesheet_entries` on those ids to recover the actual covered
--      work_dates), an `app.attendance_sessions` row for that SAME
--      work_date with `payroll_input_status='approved'` contributes ITS OWN
--      session length (`effective_clock_out_at - effective_clock_in_at`,
--      minus none -- Attendance carries no unpaid-break column, a disclosed
--      V1 bound identical to HRT-278's own single-clock-pair-per-workday
--      simplification) to REGULAR minutes ONLY -- never overtime. Overtime
--      classification structurally requires HRT-281's own governed
--      overtime-request approval (`app.overtime_requests.eligible_
--      classification`) -- an attendance session alone can never become
--      overtime pay by this fallback, exactly the recommended resolution's
--      own explicit constraint.
-- A work_date can therefore contribute through EXACTLY ONE of the two
-- sources, never both -- structurally impossible to double-count, since
-- step 2's own query excludes every work_date step 1 already covered.
--
-- This is a REAL reconciliation, not a "pick one and ignore the other"
-- shortcut -- both HRT-278's and HRT-281's own governed approval flows are
-- genuinely consumed. ISS-2026-074 is CLOSED by this migration (see
-- docs/runtime/KNOWN_ISSUES.md and this checkpoint's own build log for the
-- closure record); HRT-278.md and HRT-281.md are not edited (append-only
-- history), the closure is recorded where a reader would look for it: this
-- migration's own header, KNOWN_ISSUES.md, and HRT-282.md.
--
-- ===========================================================================
-- DECISION 3 -- RPD-016 statutory disclosure (mandatory reading item 5).
-- ===========================================================================
--
-- Mirrors FIN-195's own `app.finance_tax_codes`/`app.finance_tax_rule_
-- versions` pattern exactly (read in full before writing this migration):
-- statutory payroll components (Indonesia PPh21 income tax withholding,
-- BPJS Kesehatan, BPJS Ketenagakerjaan) are seeded as LABELS ONLY --
-- `is_statutory=true`, zero numeric rate/bracket/formula -- with exactly
-- ONE `is_example_fixture=true` version each, a STRUCTURAL placeholder
-- (`fixed_amount=0`), which `app.approve_payroll_component_version` can
-- NEVER approve (hard-blocked, mirroring `app.approve_finance_tax_rule`'s
-- identical `finance_tax_rule_example_fixture_not_activatable` guard). A
-- real statutory component version additionally requires attached, dated
-- SME evidence (`sme_evidence_reference`/`sme_evidence_date`, both
-- non-null) before `approve_payroll_component_version` will activate it --
-- this repository has NO such dated Indonesia HR/payroll/legal SME evidence
-- anywhere (confirmed by re-reading `02_CONFIRMED_DECISION_REGISTER.md`
-- RPD-016 and every prior Finance/HRIS checkpoint's own disclosure), so
-- every statutory component seeded by this migration remains, and MUST
-- remain, `status='draft'`/un-activatable until an authorized SME creates
-- a fresh, evidence-backed draft. This is a full, working engine and
-- configuration schema (Prompt 282's own instruction: "do not silently
-- skip the capability itself") -- it is the ACTIVATION GATE that is closed,
-- never the capability.
--
-- ===========================================================================
-- DECISION 4 -- RPD-023 MFA gap disclosure (mandatory reading item 5).
-- ===========================================================================
--
-- No per-action step-up MFA mechanism exists anywhere in this repository
-- yet (FIN-216's own disclosed finding, confirmed still true by this
-- checkpoint's own re-check of the live schema and every later phase's own
-- build logs through HRT-281). This migration does not build a bespoke one
-- for Payroll alone -- doing so would create a second, payroll-only
-- authentication primitive, exactly what Prompt 282's own forbidden-scope
-- language and this checkpoint's own instructions warn against. The
-- compensating controls this migration DOES build, all real and enforced:
-- maker-checker via PLT-123 (finalize requires an eligible approver
-- DISTINCT from the submitter, PLT-123's own `allow_self_approval=false`
-- default), narrow field-level masking (`app.can_view_hris_payroll_row`,
-- decision 6), and enhanced audit (every write emits `app.capture_audit_
-- event`). The residual gap -- a privileged actor's own SESSION is not
-- re-challenged at the moment of finalization/handoff-acknowledgement -- is
-- carried forward exactly as every prior Finance/HRIS checkpoint has,
-- disclosed here and in the build log, never silently claimed as closed.
--
-- ===========================================================================
-- DECISION 5 -- Payroll compensation visibility is NOT inherited from
-- org-hierarchy manager scope (Prompt 282 section 26, explicit divergence
-- from every other HRT capability's "manager sees effective team" shape).
-- ===========================================================================
--
-- Every other Phase 7 capability (Attendance, Shift/Roster, Leave,
-- Overtime/Timesheet) reuses a self-or-direct-manager-or-HRS:View predicate
-- for its person-scoped rows. Payroll's own person-scoped tables
-- (`payroll_employee_component_assignments`, `payroll_input_snapshots`,
-- `payroll_run_employee_results`, `payroll_calculation_lines`,
-- `payroll_reimbursement_requests`, `payroll_loans`, `payroll_payslips`)
-- deliberately do NOT reuse that predicate. `app.can_view_hris_payroll_row`
-- is self OR the PROTECTED `HRS:View payroll` permission specifically --
-- the SAME narrower-than-`HRS:View` shape HRT-281 already established for
-- `app.payroll_time_inputs` (its own decision 12), extended here as this
-- capability's OWN uniform person-scoped visibility rule, never a
-- manager-of predicate. A manager with no `HRS:View payroll` grant sees
-- nothing about a direct report's compensation, full stop.
--
-- ===========================================================================
-- DECISION 6 -- PLT-123 maker-checker is used for RUN FINALIZATION only,
-- not for every payroll decision (Prompt 282 section 16, "use PLT-123
-- ... unless you find and document a concrete reason it does not fit").
-- ===========================================================================
--
-- Component-version approval, employee-component assignment, reimbursement
-- decision, and loan issuance all use direct `HRS:Approve` gating (the
-- SAME single-approver-tier, self-approval-blocked shape `decide_overtime_
-- request`/`decide_timesheet_entry` already established, HRT-281) --
-- each is an independently reversible, per-item HR decision, not a
-- batch-wide fund-disbursing event. PAYROLL RUN FINALIZATION is the one
-- decision this capability makes that is genuinely irreversible in effect
-- (it freezes a period's pay figures and triggers the Finance handoff) and
-- is the ONE step Prompt 282's own main flow (section 21) names
-- explicitly ("obtains maker-checker approval, finalizes a snapshot") --
-- `app.submit_payroll_run_for_finalization`/`app.finalize_payroll_run`
-- route through `app.request_approval`/`app.decide_approval_step`
-- (PLT-123) exactly like `app.submit_leave_request`/`app.decide_leave_
-- request` (HRT-280) do, with `entity_type='payroll_run'`.
--
-- ===========================================================================
-- Further decisions (7-20), numbered for the build log's own cross-
-- reference, kept brief here and expanded in docs/build-log/phase-07/
-- HRT-282.md:
-- ===========================================================================
-- 7. One consolidated `app.payroll_periods` models BOTH calendar and period
--    (mirrors HRT-281's own `timesheet_periods` consolidation) -- never a
--    separate calendar-header table with nothing but naming duplication.
-- 8. Component calculation is bounded to `fixed_amount`, `hourly_rate`
--    (the ONE method that consumes decision 2's own resolved input
--    snapshot -- `fixed_amount` here means rate-per-hour, applied against
--    `payroll_input_snapshots.regular_minutes / 60`; this is deliberately
--    the ONLY quantity-driven method in V1 -- differentiated weekday/
--    weekend/holiday overtime-pay multipliers are NOT built, since no
--    confirmed Indonesia statutory multiplier exists to encode, matching
--    RPD-016's own "do not fabricate unconfirmed pay-rate rules" spirit;
--    overtime minutes remain fully captured/versioned in the snapshot and
--    are handed to Finance as informational time detail, disclosed, not
--    silently dropped), `percentage_of_component` (a named, resolvable
--    reference to another ACTIVE component's own computed amount within
--    the same run), and `manual_per_run` (an amount entered at assignment
--    time, e.g. a one-off allowance) -- a generic arbitrary-formula
--    expression evaluator is
--    explicitly OUT of this checkpoint's bounded scope (the same
--    proportionate-effort call FIN-200's own vendor-bill "no configurable
--    threshold-routing engine" disclosure made) -- a free-text formula
--    sandbox is a real injection/DoS surface this checkpoint declines to
--    build without a dedicated security design pass.
-- 9. Loan repayment and reimbursement payout are modeled as their OWN
--    calculation-line source (`source_type in ('loan_installment',
--    'reimbursement')`), never forced through the component/version
--    system -- they are individual employee obligations, not authored
--    tenant-wide policy.
-- 10. `net_pay = gross_earnings - total_deductions - total_tax -
--     total_loan_repayment + total_reimbursement`. `total_benefit_
--     employer_cost` (e.g. employer-side BPJS) is tracked but NEVER added
--     to net pay -- it is an employer cost/liability line for the Finance
--     handoff's GL aggregate, not an employee disbursement.
-- 11. Finalized run history never recalculates in place -- correction/
--     adjustment/off-cycle are NEW `app.payroll_runs` rows with `run_type
--     in ('correction','adjustment')` carrying `adjusts_run_id`, going
--     through the identical draft->calculate->review->finalize lifecycle.
-- 12. Exact decimals throughout (`numeric(14,2)` for every money column,
--     `numeric` for rate/percentage), explicit rounding via `round(...,
--     2)` at every computed-amount write, never a binary float.
-- 13. Opening loan balances (data migration impact, section 19) load
--     through `app.issue_payroll_loan`'s own `p_is_opening_balance`
--     parameter -- a real, disclosed, bounded cutover path (no separate
--     signed-control-total pipeline is built; a genuinely large cutover
--     import is out of this checkpoint's scope, matching every prior
--     HRIS/Finance checkpoint's own "no bulk import beyond what is built"
--     disclosure).
-- 14. RBAC: zero new `app.permissions` rows -- the twelve pre-seeded `HRS`
--     actions (View/Create/Edit/Delete/Approve/Export/View payroll/View
--     personal data/Reject/Import/Download/Override) plus the pre-seeded
--     `FIN:Edit`/`FIN:View` (the ONE cross-module gate, decision 1) cover
--     every write this checkpoint performs.
-- 15. Self-approval is blocked on every governed decision (taxonomy C-18):
--     component-version approve, reimbursement decide, and (via PLT-123's
--     own enforcement) run finalize.
-- 16. `btree_gist` is required (already enabled by HRT-275/280/281) for
--     the employee-component-assignment overlap EXCLUDE constraint.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
-- its own explicit `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM
-- PUBLIC` statement before its final grants, the standing per-migration
-- convention since PLT-118.

create extension if not exists btree_gist;

-- ===========================================================================
-- 0. Additive extension of app.leave_types (HRT-280) -- decision (see
--    build log): payroll needs to know whether a leave TYPE represents
--    paid time (no pay impact) or unpaid time (a real deduction) to
--    compute input snapshots correctly. No such column existed anywhere in
--    HRT-280's own schema. Additive ALTER, default true (preserves every
--    existing row's behavior as paid, the safe default for a new,
--    non-breaking column), mirrors HRT-279/280's own established "widen an
--    existing table via ALTER in a NEW migration, never edit the applied
--    one" convention (e.g. app.jobs.job_type widened three times already).
-- ===========================================================================

alter table app.leave_types add column is_paid boolean not null default true;

comment on column app.leave_types.is_paid is
  'HRT-282: whether an approved request of this leave type is paid (no payroll deduction) or unpaid (deducts pay in the input snapshot). Additive, default true -- preserves every pre-existing leave type''s behavior; a tenant HR admin should explicitly review and set this per type post-upgrade for accurate payroll calculation, disclosed in the build log.';

-- ===========================================================================
-- 1. app.payroll_periods -- consolidated calendar + period (decision 7).
-- ===========================================================================

create table app.payroll_periods (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  org_unit_id uuid references app.org_units (id),
  code text not null,
  period_type text not null default 'monthly',
  period_start date not null,
  period_end date not null,
  pay_date date not null,
  status text not null default 'open',
  frozen_by text,
  frozen_at timestamptz,
  frozen_employee_count integer,
  reopen_reason text,
  finalized_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_periods_code_check check (code ~ '^[a-z0-9_-]{2,60}$'),
  constraint payroll_periods_type_check check (period_type in ('monthly', 'semi_monthly', 'biweekly', 'weekly')),
  constraint payroll_periods_date_range_check check (period_end >= period_start),
  constraint payroll_periods_pay_date_check check (pay_date >= period_start),
  constraint payroll_periods_status_check check (
    status in ('open', 'input_frozen', 'calculating', 'calculated', 'under_review', 'pending_approval', 'finalized', 'cancelled')
  ),
  constraint payroll_periods_tenant_code_unique unique (tenant_id, code)
);

comment on table app.payroll_periods is
  'HRT-282 (decision 7): one row per payroll cycle window, consolidating calendar and period (mirrors app.timesheet_periods, HRT-281). status is the coarse period-level gate; the fine-grained maker-checker lifecycle lives on app.payroll_runs, since a period may carry several runs (regular + off-cycle + correction).';

create index payroll_periods_tenant_status_idx on app.payroll_periods (tenant_id, status);
create index payroll_periods_tenant_dates_idx on app.payroll_periods (tenant_id, period_start desc);

create function app.touch_payroll_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_payroll_row is
  'HRT-282: shared record_version-bump trigger for every versioned payroll table below -- reused across all of them, mirroring app.touch_overtime_timesheet_row (HRT-281), never reimplemented per-table (the exact HRT-281 self-found-defect-1 lesson applied from the start).';

create trigger payroll_periods_touch before update on app.payroll_periods
  for each row execute function app.touch_payroll_row();

-- ===========================================================================
-- 2. app.payroll_components / app.payroll_component_versions -- versioned
--    component/formula catalogue (decisions 3, 8).
-- ===========================================================================

create table app.payroll_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references app.tenants (id),
  code text not null,
  name text not null,
  component_type text not null,
  is_statutory boolean not null default false,
  gl_mapping_category text not null,
  status text not null default 'active',
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_components_code_check check (code ~ '^[a-z0-9_]{2,60}$'),
  constraint payroll_components_name_check check (length(trim(name)) > 0),
  constraint payroll_components_type_check check (
    component_type in ('earning', 'deduction', 'benefit_employer_cost', 'tax')
  ),
  constraint payroll_components_status_check check (status in ('active', 'archived')),
  constraint payroll_components_gl_mapping_check check (length(trim(gl_mapping_category)) > 0)
);

comment on table app.payroll_components is
  'HRT-282 (decision 3): the component identity catalogue. tenant_id null = platform-wide statutory label (mirrors app.finance_tax_codes'' own tenant_id-null convention, FIN-195) -- only Supreme Admin may create one (see app.create_payroll_component). component_type is bounded to earning/deduction/benefit_employer_cost/tax -- loan_repayment/reimbursement are calculation-line SOURCE types (decision 9), never components, since they are individual employee obligations, not authored policy.';

create index payroll_components_tenant_status_idx on app.payroll_components (tenant_id, status);
create unique index payroll_components_tenant_code_unique on app.payroll_components (tenant_id, code) where tenant_id is not null;
create unique index payroll_components_platform_code_unique on app.payroll_components (code) where tenant_id is null;

create table app.payroll_component_versions (
  id uuid primary key default gen_random_uuid(),
  component_id uuid not null references app.payroll_components (id),
  tenant_id uuid references app.tenants (id),
  version_number integer not null,
  status text not null default 'draft',
  calculation_method text not null,
  fixed_amount numeric(14, 2),
  percentage_rate numeric(7, 4),
  percentage_of_component_id uuid references app.payroll_components (id),
  currency text not null default 'IDR',
  effective_from date not null,
  effective_to date,
  is_example_fixture boolean not null default false,
  sme_evidence_reference text,
  sme_evidence_date date,
  sme_evidence_note text,
  published_by text,
  published_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_component_versions_status_check check (status in ('draft', 'approved', 'archived')),
  constraint payroll_component_versions_method_check check (
    calculation_method in ('fixed_amount', 'hourly_rate', 'percentage_of_component', 'manual_per_run')
  ),
  constraint payroll_component_versions_method_shape_check check (
    (calculation_method in ('fixed_amount', 'hourly_rate') and fixed_amount is not null and percentage_rate is null and percentage_of_component_id is null)
    or (calculation_method = 'percentage_of_component' and percentage_rate is not null and percentage_of_component_id is not null and fixed_amount is null)
    or (calculation_method = 'manual_per_run' and fixed_amount is null and percentage_rate is null and percentage_of_component_id is null)
  ),
  constraint payroll_component_versions_fixed_amount_check check (fixed_amount is null or fixed_amount >= 0),
  constraint payroll_component_versions_percentage_check check (percentage_rate is null or (percentage_rate >= 0 and percentage_rate <= 1000)),
  constraint payroll_component_versions_effective_range_check check (effective_to is null or effective_to >= effective_from),
  constraint payroll_component_versions_published_shape_check check (
    (status <> 'approved') or (published_at is not null and published_by is not null)
  ),
  constraint payroll_component_versions_example_fixture_check check (not is_example_fixture or status = 'draft'),
  constraint payroll_component_versions_component_version_unique unique (component_id, version_number)
);

comment on table app.payroll_component_versions is
  'HRT-282 (decisions 3, 8): versioned formula/config per component, draft -> approved -> archived, mirrors app.finance_tax_rule_versions (FIN-195) exactly for the statutory-activation gate. is_example_fixture rows can NEVER reach approved -- see app.approve_payroll_component_version.';

create index payroll_component_versions_component_status_idx on app.payroll_component_versions (component_id, status);
create index payroll_component_versions_tenant_idx on app.payroll_component_versions (tenant_id);

create trigger payroll_component_versions_touch before update on app.payroll_component_versions
  for each row execute function app.touch_payroll_row();

-- Seeded LABELS ONLY (decision 3) -- zero numeric rate/bracket implied.
insert into app.payroll_components (tenant_id, code, name, component_type, is_statutory, gl_mapping_category, status, created_by) values
  (null, 'pph21', 'PPh 21 - Income Tax Withholding (Employee)', 'tax', true, 'statutory_tax_payable', 'active', 'payroll-foundation'),
  (null, 'bpjs_kesehatan_employee', 'BPJS Kesehatan - Employee Contribution', 'deduction', true, 'statutory_benefit_payable', 'active', 'payroll-foundation'),
  (null, 'bpjs_kesehatan_employer', 'BPJS Kesehatan - Employer Contribution', 'benefit_employer_cost', true, 'statutory_benefit_expense', 'active', 'payroll-foundation'),
  (null, 'bpjs_tk_jht_employee', 'BPJS Ketenagakerjaan JHT - Employee Contribution', 'deduction', true, 'statutory_benefit_payable', 'active', 'payroll-foundation'),
  (null, 'bpjs_tk_jht_employer', 'BPJS Ketenagakerjaan JHT - Employer Contribution', 'benefit_employer_cost', true, 'statutory_benefit_expense', 'active', 'payroll-foundation');

insert into app.payroll_component_versions (
  component_id, tenant_id, version_number, status, calculation_method, fixed_amount, currency, effective_from, is_example_fixture, created_by
)
select id, null, 1, 'draft', 'fixed_amount', 0, 'IDR', '2026-01-01'::date, true, 'payroll-foundation'
from app.payroll_components where tenant_id is null and is_statutory;

comment on table app.payroll_component_versions is
  'HRT-282 (decision 3): EXAMPLE FIXTURE VERSIONS ARE NOT VERIFIED RATES. fixed_amount=0 is a structural placeholder, not a real Indonesian PPh21/BPJS figure. An authorized HR/Payroll/Finance/Legal SME must create a fresh, evidence-backed draft (app.create_payroll_component_version) and approve it (app.approve_payroll_component_version, which requires attached dated evidence) before any real statutory calculation is possible for a tenant. These seeded fixtures can never themselves be approved -- see app.approve_payroll_component_version''s own is_example_fixture guard.';

-- ===========================================================================
-- 3. app.payroll_employee_component_assignments -- effective-dated employee
--    <-> component binding with an optional override amount/rate.
-- ===========================================================================

create table app.payroll_employee_component_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  component_id uuid not null references app.payroll_components (id),
  override_amount numeric(14, 2),
  override_percentage numeric(7, 4),
  manual_amount numeric(14, 2),
  currency text not null default 'IDR',
  effective_from date not null,
  effective_to date,
  status text not null default 'active',
  end_reason text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  validity_range daterange generated always as (daterange(effective_from, effective_to, '[]')) stored,
  constraint payroll_employee_component_assignments_status_check check (status in ('active', 'ended')),
  constraint payroll_employee_component_assignments_effective_range_check check (effective_to is null or effective_to >= effective_from),
  constraint payroll_employee_component_assignments_override_amount_check check (override_amount is null or override_amount >= 0),
  constraint payroll_employee_component_assignments_override_pct_check check (override_percentage is null or (override_percentage >= 0 and override_percentage <= 1000)),
  constraint payroll_employee_component_assignments_manual_amount_check check (manual_amount is null or manual_amount >= 0),
  constraint payroll_employee_component_assignments_end_shape_check check (status <> 'ended' or (end_reason is not null and length(trim(end_reason)) > 0))
);

comment on table app.payroll_employee_component_assignments is
  'HRT-282: which components apply to which employee, and when. override_amount/override_percentage/manual_amount let one employee''s assignment diverge from the component version''s own default without authoring a second component -- e.g. one employee''s specific transport allowance figure. EXCLUDE constraint below enforces at most one ACTIVE assignment per (employee, component) over any overlapping date range -- never an ambiguous double assignment.';

create index payroll_employee_component_assignments_tenant_employee_idx on app.payroll_employee_component_assignments (tenant_id, employee_id);
create index payroll_employee_component_assignments_component_idx on app.payroll_employee_component_assignments (component_id);

alter table app.payroll_employee_component_assignments
  add constraint payroll_employee_component_assignments_no_overlap
  exclude using gist (employee_id with =, component_id with =, validity_range with &&) where (status = 'active');

create trigger payroll_employee_component_assignments_touch before update on app.payroll_employee_component_assignments
  for each row execute function app.touch_payroll_row();

-- ===========================================================================
-- 4. app.payroll_reimbursement_requests -- governed employee expense
--    reimbursement (decision 9).
-- ===========================================================================

create table app.payroll_reimbursement_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  category text not null,
  amount numeric(14, 2) not null,
  currency text not null default 'IDR',
  expense_date date not null,
  description text not null,
  evidence_file_id uuid references app.files (id),
  status text not null default 'draft',
  applied_payroll_period_id uuid references app.payroll_periods (id),
  requested_by_auth_user_id uuid not null,
  requested_by text,
  decided_by text,
  decided_at timestamptz,
  decided_reason text,
  cancel_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_reimbursement_requests_category_check check (category ~ '^[a-z0-9_]{2,60}$'),
  constraint payroll_reimbursement_requests_amount_check check (amount > 0),
  constraint payroll_reimbursement_requests_description_check check (length(trim(description)) > 0),
  constraint payroll_reimbursement_requests_status_check check (status in ('draft', 'pending_approval', 'approved', 'rejected', 'cancelled', 'paid')),
  constraint payroll_reimbursement_requests_decided_shape_check check (
    (status in ('draft', 'pending_approval') and decided_at is null and decided_by is null)
    or (status = 'cancelled')
    or (status in ('approved', 'rejected') and decided_at is not null and decided_by is not null and decided_reason is not null and length(trim(decided_reason)) > 0)
    or (status = 'paid')
  ),
  constraint payroll_reimbursement_requests_cancel_reason_check check (status <> 'cancelled' or (cancel_reason is not null and length(trim(cancel_reason)) > 0))
);

comment on table app.payroll_reimbursement_requests is
  'HRT-282 (decision 9): governed employee expense reimbursement -- draft -> pending_approval -> approved/rejected, then paid once a finalized run''s calculation line consumes it. Direct HRS:Approve decide (decision 6), never PLT-123 -- an independently reversible per-item HR decision, matching HRT-281''s own overtime/timesheet decide shape.';

create index payroll_reimbursement_requests_tenant_employee_idx on app.payroll_reimbursement_requests (tenant_id, employee_id);
create index payroll_reimbursement_requests_tenant_status_idx on app.payroll_reimbursement_requests (tenant_id, status);
create unique index payroll_reimbursement_requests_idempotency_unique on app.payroll_reimbursement_requests (tenant_id, employee_id, idempotency_key) where idempotency_key is not null;

create trigger payroll_reimbursement_requests_touch before update on app.payroll_reimbursement_requests
  for each row execute function app.touch_payroll_row();

-- ===========================================================================
-- 5. app.payroll_loans / app.payroll_loan_installments (decision 9, 13).
-- ===========================================================================

create table app.payroll_loans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  employee_id uuid not null references app.employees (master_record_id),
  principal_amount numeric(14, 2) not null,
  currency text not null default 'IDR',
  installment_amount numeric(14, 2) not null,
  term_count integer not null,
  remaining_installments integer not null,
  status text not null default 'active',
  is_opening_balance boolean not null default false,
  notes text,
  cancel_reason text,
  issued_by text,
  issued_at timestamptz not null default now(),
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_loans_principal_check check (principal_amount > 0),
  constraint payroll_loans_installment_check check (installment_amount > 0),
  constraint payroll_loans_term_check check (term_count > 0 and term_count <= 360),
  constraint payroll_loans_remaining_check check (remaining_installments >= 0 and remaining_installments <= term_count),
  constraint payroll_loans_status_check check (status in ('active', 'completed', 'cancelled'))
);

comment on table app.payroll_loans is
  'HRT-282 (decisions 9, 13): an employee loan/advance, deducted one scheduled installment per period until remaining_installments reaches 0 (then status auto-completes). is_opening_balance=true is the disclosed, bounded cutover path (decision 13) for a loan already mid-repayment when this capability goes live.';

create index payroll_loans_tenant_employee_idx on app.payroll_loans (tenant_id, employee_id);
create index payroll_loans_tenant_status_idx on app.payroll_loans (tenant_id, status);

create trigger payroll_loans_touch before update on app.payroll_loans
  for each row execute function app.touch_payroll_row();

create table app.payroll_loan_installments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references app.payroll_loans (id),
  tenant_id uuid not null references app.tenants (id),
  installment_number integer not null,
  amount numeric(14, 2) not null,
  status text not null default 'scheduled',
  payroll_period_id uuid references app.payroll_periods (id),
  deducted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint payroll_loan_installments_amount_check check (amount > 0),
  constraint payroll_loan_installments_status_check check (status in ('scheduled', 'deducted', 'waived')),
  constraint payroll_loan_installments_loan_number_unique unique (loan_id, installment_number)
);

comment on table app.payroll_loan_installments is
  'HRT-282: one row per scheduled installment. payroll_period_id/deducted_at are set only when a run''s input-snapshot freeze actually consumes this installment as a calculation line -- a scheduled-but-not-yet-reached installment carries both null.';

create index payroll_loan_installments_tenant_status_idx on app.payroll_loan_installments (tenant_id, status);
create unique index payroll_loan_installments_next_scheduled_idx on app.payroll_loan_installments (loan_id, installment_number) where status = 'scheduled';

-- ===========================================================================
-- 6. app.payroll_input_snapshots -- the frozen, per (period, employee) input
--    package (decision 2, the ISS-2026-074 resolution).
-- ===========================================================================

create table app.payroll_input_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  payroll_period_id uuid not null references app.payroll_periods (id),
  employee_id uuid not null references app.employees (master_record_id),
  regular_minutes integer not null default 0,
  overtime_weekday_minutes integer not null default 0,
  overtime_weekend_minutes integer not null default 0,
  overtime_holiday_minutes integer not null default 0,
  paid_leave_units numeric(9, 2) not null default 0,
  unpaid_leave_units numeric(9, 2) not null default 0,
  source_payroll_time_input_ids uuid[] not null default array[]::uuid[],
  source_attendance_session_ids uuid[] not null default array[]::uuid[],
  source_leave_request_ids uuid[] not null default array[]::uuid[],
  frozen_by text,
  frozen_at timestamptz not null default now(),
  constraint payroll_input_snapshots_minutes_nonneg_check check (
    regular_minutes >= 0 and overtime_weekday_minutes >= 0 and overtime_weekend_minutes >= 0 and overtime_holiday_minutes >= 0
  ),
  constraint payroll_input_snapshots_leave_nonneg_check check (paid_leave_units >= 0 and unpaid_leave_units >= 0),
  constraint payroll_input_snapshots_period_employee_unique unique (payroll_period_id, employee_id)
);

comment on table app.payroll_input_snapshots is
  'HRT-282 (decision 2, ISS-2026-074 resolution): the one frozen input record per (period, employee) -- genuinely immutable once written (app.freeze_payroll_period_inputs INSERTs once; re-freezing after a reopen DELETEs and re-INSERTs for that period, never an UPDATE of a live figure). regular_minutes/overtime_*_minutes are computed by app._resolve_payroll_time_inputs_for_period, which reads BOTH app.payroll_time_inputs (HRT-281, timesheet-entries-derived, authoritative per work_date it covers) and app.attendance_sessions (HRT-278, approved sessions, regular-time-only fallback for any work_date NOT covered by the former) -- see this migration''s own header decision 2 for the full precedence rule and the double-counting proof.';

create index payroll_input_snapshots_tenant_period_idx on app.payroll_input_snapshots (tenant_id, payroll_period_id);
create index payroll_input_snapshots_employee_idx on app.payroll_input_snapshots (employee_id);

-- ===========================================================================
-- 7. app.payroll_runs -- the maker-checker-governed batch/run header
--    (decision 6, 11).
-- ===========================================================================

create table app.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  payroll_period_id uuid not null references app.payroll_periods (id),
  run_type text not null default 'regular',
  adjusts_run_id uuid references app.payroll_runs (id),
  status text not null default 'draft',
  currency text not null default 'IDR',
  employee_count integer not null default 0,
  exception_count integer not null default 0,
  job_id uuid references app.jobs (job_id),
  calculated_by text,
  calculated_at timestamptz,
  approval_request_id uuid references app.approval_requests (id),
  submitted_by text,
  submitted_at timestamptz,
  finalized_by text,
  finalized_at timestamptz,
  decided_reason text,
  cancel_reason text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_runs_type_check check (run_type in ('regular', 'off_cycle', 'correction', 'adjustment')),
  constraint payroll_runs_status_check check (
    status in ('draft', 'calculating', 'calculated', 'exception', 'pending_approval', 'finalized', 'cancelled')
  ),
  constraint payroll_runs_adjusts_shape_check check (run_type not in ('correction', 'adjustment') or adjusts_run_id is not null),
  constraint payroll_runs_not_self_adjust_check check (adjusts_run_id is distinct from id),
  constraint payroll_runs_counts_nonneg_check check (employee_count >= 0 and exception_count >= 0)
);

comment on table app.payroll_runs is
  'HRT-282 (decisions 6, 11): one execution attempt against a period. Several runs may exist per period (one regular plus any number of off_cycle/correction/adjustment). Finalized runs are never recalculated in place (business rule, section 24) -- a correction is a NEW row with adjusts_run_id pointing at the run being corrected. approval_request_id is PLT-123''s own app.approval_requests row, used ONLY for the submit-for-finalization -> finalize step (decision 6) -- every earlier stage uses direct HRS:Approve gating.';

create index payroll_runs_tenant_period_idx on app.payroll_runs (tenant_id, payroll_period_id);
create index payroll_runs_tenant_status_idx on app.payroll_runs (tenant_id, status);
create unique index payroll_runs_idempotency_unique on app.payroll_runs (tenant_id, idempotency_key) where idempotency_key is not null;
-- At most one non-terminal run of the same type per period -- prevents two
-- concurrently-in-flight regular runs for the same period (a correction/
-- adjustment/off_cycle run is deliberately excluded from this constraint,
-- since several of THOSE may legitimately coexist against one period).
create unique index payroll_runs_one_active_regular_per_period on app.payroll_runs (payroll_period_id)
  where run_type = 'regular' and status not in ('finalized', 'cancelled');

create trigger payroll_runs_touch before update on app.payroll_runs
  for each row execute function app.touch_payroll_row();

-- ===========================================================================
-- 8. app.payroll_calculation_lines -- the calculation detail (decision 9).
-- ===========================================================================

create table app.payroll_calculation_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  payroll_run_id uuid not null references app.payroll_runs (id),
  employee_id uuid not null references app.employees (master_record_id),
  source_type text not null,
  component_id uuid references app.payroll_components (id),
  component_version_id uuid references app.payroll_component_versions (id),
  loan_installment_id uuid references app.payroll_loan_installments (id),
  reimbursement_request_id uuid references app.payroll_reimbursement_requests (id),
  line_type text not null,
  quantity numeric(12, 2),
  rate numeric(14, 4),
  amount numeric(14, 2) not null,
  currency text not null,
  description text,
  created_at timestamptz not null default now(),
  constraint payroll_calculation_lines_source_type_check check (source_type in ('component', 'loan_installment', 'reimbursement')),
  constraint payroll_calculation_lines_line_type_check check (
    line_type in ('earning', 'deduction', 'benefit_employer_cost', 'tax', 'loan_repayment', 'reimbursement')
  ),
  constraint payroll_calculation_lines_amount_nonneg_check check (amount >= 0),
  constraint payroll_calculation_lines_source_shape_check check (
    (source_type = 'component' and component_id is not null and component_version_id is not null and loan_installment_id is null and reimbursement_request_id is null)
    or (source_type = 'loan_installment' and loan_installment_id is not null and component_id is null and component_version_id is null and reimbursement_request_id is null and line_type = 'loan_repayment')
    or (source_type = 'reimbursement' and reimbursement_request_id is not null and component_id is null and component_version_id is null and loan_installment_id is null and line_type = 'reimbursement')
  )
);

comment on table app.payroll_calculation_lines is
  'HRT-282 (decision 9): one row per employee per run per contributing item. Genuinely append-only per run -- app.calculate_payroll_run DELETEs and re-inserts a given employee''s own lines only while the run is still pre-finalization (draft/calculated/exception), never after finalized (business rule, section 24: finalized history never silently recalculates).';

create index payroll_calculation_lines_run_employee_idx on app.payroll_calculation_lines (payroll_run_id, employee_id);
create index payroll_calculation_lines_tenant_idx on app.payroll_calculation_lines (tenant_id, payroll_run_id);

-- ===========================================================================
-- 9. app.payroll_run_employee_results -- per-employee totals for a run.
-- ===========================================================================

create table app.payroll_run_employee_results (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  payroll_run_id uuid not null references app.payroll_runs (id),
  employee_id uuid not null references app.employees (master_record_id),
  input_snapshot_id uuid references app.payroll_input_snapshots (id),
  status text not null default 'calculated',
  currency text not null,
  gross_earnings numeric(14, 2) not null default 0,
  total_deductions numeric(14, 2) not null default 0,
  total_tax numeric(14, 2) not null default 0,
  total_benefit_employer_cost numeric(14, 2) not null default 0,
  total_reimbursement numeric(14, 2) not null default 0,
  total_loan_repayment numeric(14, 2) not null default 0,
  net_pay numeric(14, 2) not null default 0,
  calculated_at timestamptz not null default now(),
  constraint payroll_run_employee_results_status_check check (status in ('calculated', 'exception', 'reviewed')),
  constraint payroll_run_employee_results_amounts_nonneg_check check (
    gross_earnings >= 0 and total_deductions >= 0 and total_tax >= 0 and total_benefit_employer_cost >= 0
    and total_reimbursement >= 0 and total_loan_repayment >= 0
  ),
  constraint payroll_run_employee_results_run_employee_unique unique (payroll_run_id, employee_id)
);

comment on table app.payroll_run_employee_results is
  'HRT-282 (decision 10): net_pay = gross_earnings - total_deductions - total_tax - total_loan_repayment + total_reimbursement. total_benefit_employer_cost is tracked but structurally excluded from net_pay -- an employer-side cost/liability, never an employee disbursement (see this migration''s own header decision 10).';

create index payroll_run_employee_results_tenant_run_idx on app.payroll_run_employee_results (tenant_id, payroll_run_id);
create index payroll_run_employee_results_employee_idx on app.payroll_run_employee_results (employee_id);

-- ===========================================================================
-- 10. app.payroll_exceptions -- review/exception handling.
-- ===========================================================================

create table app.payroll_exceptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  payroll_run_id uuid not null references app.payroll_runs (id),
  employee_id uuid references app.employees (master_record_id),
  exception_type text not null,
  severity text not null default 'medium',
  message text not null,
  status text not null default 'open',
  resolved_by text,
  resolved_at timestamptz,
  resolution_note text,
  created_at timestamptz not null default now(),
  constraint payroll_exceptions_severity_check check (severity in ('low', 'medium', 'high')),
  constraint payroll_exceptions_status_check check (status in ('open', 'resolved', 'waived')),
  constraint payroll_exceptions_message_check check (length(trim(message)) > 0),
  constraint payroll_exceptions_resolved_shape_check check (
    (status = 'open' and resolved_at is null and resolved_by is null)
    or (status in ('resolved', 'waived') and resolved_at is not null and resolved_by is not null)
  )
);

comment on table app.payroll_exceptions is
  'HRT-282: a review-blocking finding raised during app.calculate_payroll_run (e.g. missing input snapshot, negative net pay, currency mismatch across an employee''s own assigned components). A run cannot be submitted for finalization (app.submit_payroll_run_for_finalization) while any OPEN exception exists for it -- resolved (HRS:Edit) or waived (HRS:Override) clears the block.';

create index payroll_exceptions_run_status_idx on app.payroll_exceptions (payroll_run_id, status);
create index payroll_exceptions_tenant_idx on app.payroll_exceptions (tenant_id);

-- ===========================================================================
-- 11. app.payroll_payslips -- private, per-employee, per-finalized-run
--     payslip (decision 12).
-- ===========================================================================

create table app.payroll_payslips (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  payroll_run_id uuid not null references app.payroll_runs (id),
  payroll_period_id uuid not null references app.payroll_periods (id),
  employee_id uuid not null references app.employees (master_record_id),
  currency text not null,
  gross_earnings numeric(14, 2) not null,
  total_deductions numeric(14, 2) not null,
  total_tax numeric(14, 2) not null,
  total_benefit_employer_cost numeric(14, 2) not null,
  total_reimbursement numeric(14, 2) not null,
  total_loan_repayment numeric(14, 2) not null,
  net_pay numeric(14, 2) not null,
  line_items jsonb not null,
  generated_by text,
  generated_at timestamptz not null default now(),
  constraint payroll_payslips_run_employee_unique unique (payroll_run_id, employee_id)
);

comment on table app.payroll_payslips is
  'HRT-282: generated ONCE, at app.finalize_payroll_run''s own approve branch, from that run''s own already-computed app.payroll_run_employee_results/app.payroll_calculation_lines -- never editable afterward (no UPDATE grant to any role but service_role, no update-shaped RPC exists). line_items is built via an explicit jsonb_build_object allowlist (component_code/component_type/amount/currency ONLY) -- never to_jsonb(whole_row) (taxonomy C-07): no free-text/PII field is ever copied into it.';

create index payroll_payslips_tenant_employee_idx on app.payroll_payslips (tenant_id, employee_id);
create index payroll_payslips_period_idx on app.payroll_payslips (payroll_period_id);

-- ===========================================================================
-- 12. Widen the generic job-type single source of truth (ATW-031,
--     ISS-2026-012) to add 'payroll_calculation' -- reuses PLT-131/132's
--     existing durable job framework directly (mandatory reading item 9),
--     never a second queue mechanism. The FOURTH HRIS-domain adopter after
--     HRT-279's 'roster_generation' and HRT-280's 'leave_accrual'/
--     'leave_carry_forward_expiry'.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'HRT-282 (decision, mandatory reading item 9): widened to add ''payroll_calculation'' -- the fourth HRIS-domain adopter of PLT-132''s own generic job_type list. Kept set-equal with app.generic_job_types() by scripts/db-tests/background-job-framework.sql''s own standing ATW-031 drift-gate assertion.';

create or replace function app.generic_job_types()
returns text[]
language sql
immutable
set search_path = app, pg_temp
as $$
  select array[
    'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012), widened by HRT-282 to add ''payroll_calculation''. The single authority for which job_type values the GENERIC queue mechanics accept -- app.enqueue_job and app.dispatch_event_as_job both already call this function directly, unchanged by this migration.';

-- ===========================================================================
-- 13. Authority/visibility helpers.
-- ===========================================================================

create function app.check_payroll_authority(p_action text, p_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = app, pg_temp
as $$
  select (app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'HRS', p_action)).allowed;
$$;

comment on function app.check_payroll_authority is
  'HRT-282: HRS:Edit gates draft/author/create actions; HRS:Approve gates approve/decide/issue/submit-for-finalization; HRS:View payroll gates every sensitive read (decision 5, never plain HRS:View); HRS:Override gates period reopen and exception waive. SECURITY DEFINER from the start (HRT-281''s own self-found-defect-3 lesson: a bare SECURITY INVOKER wrapper around app.evaluate_permission fails for any RLS policy expression, which evaluates as the querying `authenticated` role, not this function''s owner) -- also directly usable from RLS policies below, never a second helper.';

create function app.can_view_hris_payroll_row(p_tenant_id uuid, p_employee_id uuid, p_auth_user_id uuid default auth.uid())
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  if p_tenant_id is null or p_employee_id is null then
    return false;
  end if;
  if not app.has_active_tenant_membership(p_tenant_id, p_auth_user_id) then
    return false;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_auth_user_id);
  if v_self.master_record_id is not null and v_self.master_record_id = p_employee_id then
    return true;
  end if;
  return (app.evaluate_permission(p_auth_user_id, p_tenant_id, 'HRS', 'View payroll')).allowed;
end;
$$;

comment on function app.can_view_hris_payroll_row is
  'HRT-282 (decision 5): self OR the PROTECTED HRS:View payroll permission specifically -- NEVER plain HRS:View and NEVER a manager-of-employee predicate, the deliberate divergence from every other HRT capability''s "manager sees effective team" shape (Prompt 282 section 26). SECURITY DEFINER so its own internal app.evaluate_permission call runs as this function''s owner, mirroring app.can_view_hris_payroll_time_input_row (HRT-281) exactly.';

create function app._check_payroll_component_authority(p_action text, p_component_tenant_id uuid, p_actor_auth_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
begin
  -- Platform-wide (tenant_id null) component/version: Supreme Admin only,
  -- mirrors FIN-195's own null-tenant fallback exactly. Tenant-scoped:
  -- ordinary HRS:<action> for that tenant.
  if p_component_tenant_id is null then
    return app.is_supreme_admin(p_actor_auth_user_id);
  end if;
  return app.check_payroll_authority(p_action, p_component_tenant_id, p_actor_auth_user_id);
end;
$$;

-- ===========================================================================
-- 14. app.payroll_periods lifecycle: create / freeze / reopen.
-- ===========================================================================

create function app.create_payroll_period(
  p_tenant_id uuid, p_org_unit_id uuid, p_code text, p_period_type text,
  p_period_start date, p_period_end date, p_pay_date date,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
begin
  if not app.check_payroll_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_period from app.payroll_periods where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_period;
  end if;

  insert into app.payroll_periods (tenant_id, org_unit_id, code, period_type, period_start, period_end, pay_date, created_by)
  values (p_tenant_id, p_org_unit_id, p_code, coalesce(p_period_type, 'monthly'), p_period_start, p_period_end, p_pay_date, p_actor_label)
  returning * into v_period;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_period',
    'app.payroll_periods', v_period.id, 'success', null, null, jsonb_build_object('code', p_code)
  );

  return v_period;
end;
$$;

comment on function app.create_payroll_period is
  'HRT-282: idempotent on (tenant_id, code) -- a replay with the same code returns the existing row unchanged, matching this repository''s own established idempotent-create shape.';

-- The ISS-2026-074 resolution (decision 2) -- reads BOTH app.payroll_time_
-- inputs (HRT-281) and app.attendance_sessions (HRT-278) for one employee
-- over one date range, applying the documented per-work-date precedence.
create function app._resolve_payroll_time_inputs_for_period(
  p_tenant_id uuid, p_employee_id uuid, p_period_start date, p_period_end date
)
returns table (
  regular_minutes integer, overtime_weekday_minutes integer, overtime_weekend_minutes integer, overtime_holiday_minutes integer,
  source_payroll_time_input_ids uuid[], source_attendance_session_ids uuid[]
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_ts_regular integer := 0;
  v_ts_ow integer := 0;
  v_ts_owe integer := 0;
  v_ts_oh integer := 0;
  v_covered_dates date[] := array[]::date[];
  v_pti_ids uuid[] := array[]::uuid[];
  v_att_regular integer := 0;
  v_att_ids uuid[] := array[]::uuid[];
begin
  -- Step 1: every ACTIVE app.payroll_time_inputs row whose own
  -- app.timesheet_periods window falls inside the requested payroll period
  -- range contributes its own totals as-is, and its own source_entry_ids
  -- (joined back to app.timesheet_entries) mark which work_dates are
  -- already covered.
  select
    coalesce(sum(pti.regular_minutes), 0), coalesce(sum(pti.overtime_weekday_minutes), 0),
    coalesce(sum(pti.overtime_weekend_minutes), 0), coalesce(sum(pti.overtime_holiday_minutes), 0),
    coalesce(array_agg(pti.id), array[]::uuid[])
  into v_ts_regular, v_ts_ow, v_ts_owe, v_ts_oh, v_pti_ids
  from app.payroll_time_inputs pti
  join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
  where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
    and tp.period_start >= p_period_start and tp.period_end <= p_period_end;

  select coalesce(array_agg(distinct te.work_date), array[]::date[]) into v_covered_dates
  from app.payroll_time_inputs pti
  join app.timesheet_periods tp on tp.id = pti.timesheet_period_id
  join app.timesheet_entries te on te.id = any (pti.source_entry_ids)
  where pti.tenant_id = p_tenant_id and pti.employee_id = p_employee_id and pti.status = 'active'
    and tp.period_start >= p_period_start and tp.period_end <= p_period_end;

  -- Step 2: approved attendance sessions for any work_date in range NOT
  -- already covered by step 1 -- regular minutes ONLY, never overtime.
  select
    coalesce(sum(greatest(0, round(extract(epoch from (s.effective_clock_out_at - s.effective_clock_in_at)) / 60)))::integer, 0),
    coalesce(array_agg(s.id), array[]::uuid[])
  into v_att_regular, v_att_ids
  from app.attendance_sessions s
  where s.tenant_id = p_tenant_id and s.employee_id = p_employee_id
    and s.work_date between p_period_start and p_period_end
    and s.payroll_input_status = 'approved'
    and s.effective_clock_in_at is not null and s.effective_clock_out_at is not null
    and not (s.work_date = any (v_covered_dates));

  regular_minutes := v_ts_regular + v_att_regular;
  overtime_weekday_minutes := v_ts_ow;
  overtime_weekend_minutes := v_ts_owe;
  overtime_holiday_minutes := v_ts_oh;
  source_payroll_time_input_ids := v_pti_ids;
  source_attendance_session_ids := v_att_ids;
  return next;
end;
$$;

comment on function app._resolve_payroll_time_inputs_for_period is
  'HRT-282 (decision 2, ISS-2026-074 resolution): the ONE function implementing the documented work-date-level precedence between HRT-281''s app.payroll_time_inputs and HRT-278''s app.attendance_sessions. A work_date contributes through exactly one source, never both -- see this migration''s own header for the full proof. service_role only -- called exclusively from app._build_payroll_input_snapshot_for_employee.';

create function app._build_payroll_input_snapshot_for_employee(
  p_tenant_id uuid, p_period_id uuid, p_employee_id uuid, p_period_start date, p_period_end date, p_actor_label text
)
returns app.payroll_input_snapshots
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_time record;
  v_paid_leave numeric(9, 2) := 0;
  v_unpaid_leave numeric(9, 2) := 0;
  v_leave_ids uuid[] := array[]::uuid[];
  v_snapshot app.payroll_input_snapshots;
begin
  select * into v_time from app._resolve_payroll_time_inputs_for_period(p_tenant_id, p_employee_id, p_period_start, p_period_end);

  select
    coalesce(sum(total_units) filter (where lt.is_paid), 0),
    coalesce(sum(total_units) filter (where not lt.is_paid), 0),
    coalesce(array_agg(lr.id), array[]::uuid[])
  into v_paid_leave, v_unpaid_leave, v_leave_ids
  from app.leave_requests lr
  join app.leave_types lt on lt.id = lr.leave_type_id
  where lr.tenant_id = p_tenant_id and lr.employee_id = p_employee_id
    and lr.status = 'approved' and lr.payroll_input_status = 'approved'
    and lr.date_from <= p_period_end and lr.date_to >= p_period_start;

  insert into app.payroll_input_snapshots (
    tenant_id, payroll_period_id, employee_id, regular_minutes, overtime_weekday_minutes, overtime_weekend_minutes,
    overtime_holiday_minutes, paid_leave_units, unpaid_leave_units, source_payroll_time_input_ids, source_attendance_session_ids,
    source_leave_request_ids, frozen_by
  ) values (
    p_tenant_id, p_period_id, p_employee_id, v_time.regular_minutes, v_time.overtime_weekday_minutes, v_time.overtime_weekend_minutes,
    v_time.overtime_holiday_minutes, v_paid_leave, v_unpaid_leave, v_time.source_payroll_time_input_ids, v_time.source_attendance_session_ids,
    v_leave_ids, p_actor_label
  )
  returning * into v_snapshot;

  return v_snapshot;
end;
$$;

comment on function app._build_payroll_input_snapshot_for_employee is
  'HRT-282: composes app._resolve_payroll_time_inputs_for_period''s time resolution with HRT-280''s own governed leave-payroll-approval (app.leave_requests.payroll_input_status=''approved'', decision 2) into one frozen snapshot row. service_role only -- called exclusively from app.freeze_payroll_period_inputs.';

create function app.freeze_payroll_period_inputs(p_period_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
  v_employee record;
  v_count integer := 0;
begin
  select * into v_period from app.payroll_periods where id = p_period_id for update;
  if not found then
    raise exception 'payroll_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_period.status not in ('open', 'input_frozen') then
    raise exception 'invalid_transition: period % is %, only open/input_frozen may (re)freeze inputs', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  delete from app.payroll_input_snapshots where payroll_period_id = p_period_id;

  for v_employee in
    select * from app.employees where tenant_id = v_period.tenant_id and lifecycle_status in ('active', 'on_leave')
      and (v_period.org_unit_id is null or company_org_unit_id = v_period.org_unit_id or branch_org_unit_id = v_period.org_unit_id)
  loop
    perform app._build_payroll_input_snapshot_for_employee(
      v_period.tenant_id, p_period_id, v_employee.master_record_id, v_period.period_start, v_period.period_end, p_actor_label
    );
    v_count := v_count + 1;
  end loop;

  update app.payroll_periods
  set status = 'input_frozen', frozen_by = p_actor_label, frozen_at = now(), frozen_employee_count = v_count, reopen_reason = null
  where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  if not found then
    raise exception 'stale_version: concurrent update detected for period %', p_period_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'freeze_payroll_period_inputs',
    'app.payroll_periods', v_period.id, 'success', null, null, jsonb_build_object('employee_count', v_count)
  );

  return v_period;
end;
$$;

comment on function app.freeze_payroll_period_inputs is
  'HRT-282: bounded, synchronous per-period input freeze (section 17''s own "no unbounded scan" -- bounded to this ONE period''s own active/on_leave employees, org_unit-scoped when the period itself is). Re-callable while still open/input_frozen (a genuine re-freeze after a reopen, decision 2) -- DELETEs and re-INSERTs snapshot rows for this period only, never once a run has advanced past calculated for it (enforced by app.reopen_payroll_period_inputs below, which is the only path back to input_frozen after calculation has started).';

create function app.reopen_payroll_period_inputs(p_period_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
  v_advanced_run_count integer;
begin
  select * into v_period from app.payroll_periods where id = p_period_id for update;
  if not found then
    raise exception 'payroll_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Override', v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_period.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_period.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_period.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to reopen frozen inputs' using errcode = 'check_violation';
  end if;
  if v_period.status <> 'input_frozen' then
    raise exception 'invalid_transition: period % is %, only input_frozen may reopen', p_period_id, v_period.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_advanced_run_count from app.payroll_runs
    where payroll_period_id = p_period_id and status not in ('draft', 'cancelled');
  if v_advanced_run_count > 0 then
    raise exception 'payroll_period_has_advanced_run: period % has a run already past draft -- cancel it first' , p_period_id
      using errcode = 'check_violation';
  end if;

  update app.payroll_periods set status = 'open', reopen_reason = p_reason where id = p_period_id and record_version = p_expected_version
  returning * into v_period;
  if not found then
    raise exception 'stale_version: concurrent update detected for period %', p_period_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_period.tenant_id, p_actor_auth_user_id, p_actor_label, 'reopen_payroll_period_inputs',
    'app.payroll_periods', v_period.id, 'success', p_reason, null, null
  );

  return v_period;
end;
$$;

comment on function app.reopen_payroll_period_inputs is
  'HRT-282: HRS:Override-gated, blocked while any run for this period has advanced past draft -- prevents reopening inputs out from under a run that has already calculated/is under review/pending approval/finalized.';

-- ===========================================================================
-- 15. Component / component-version authoring lifecycle (decisions 3, 6, 8).
-- ===========================================================================

create function app.create_payroll_component(
  p_tenant_id uuid, p_code text, p_name text, p_component_type text, p_gl_mapping_category text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_components
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.payroll_components;
begin
  if not app.check_payroll_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_component_type not in ('earning', 'deduction', 'benefit_employer_cost', 'tax') then
    raise exception 'invalid_component_type: % is not a supported component type', p_component_type using errcode = 'check_violation';
  end if;

  select * into v_component from app.payroll_components where tenant_id = p_tenant_id and code = p_code;
  if found then
    return v_component;
  end if;

  insert into app.payroll_components (tenant_id, code, name, component_type, is_statutory, gl_mapping_category, created_by)
  values (p_tenant_id, p_code, p_name, p_component_type, false, p_gl_mapping_category, p_actor_label)
  returning * into v_component;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_component',
    'app.payroll_components', v_component.id, 'success', null, null, jsonb_build_object('code', p_code, 'component_type', p_component_type)
  );

  return v_component;
end;
$$;

comment on function app.create_payroll_component is
  'HRT-282 (decision 3): tenant-scoped only -- a caller can never create a tenant_id-null platform-wide statutory label through this entrypoint (is_statutory is hardcoded false here); those are seeded, Supreme-Admin-owned rows only. Idempotent on (tenant_id, code).';

create function app.create_payroll_component_version(
  p_component_id uuid, p_calculation_method text, p_fixed_amount numeric, p_percentage_rate numeric,
  p_percentage_of_component_id uuid, p_currency text, p_effective_from date,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_component_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.payroll_components;
  v_version app.payroll_component_versions;
  v_next_version integer;
begin
  select * into v_component from app.payroll_components where id = p_component_id;
  if not found then
    raise exception 'payroll_component_not_found: %', p_component_id using errcode = 'no_data_found';
  end if;
  if not app._check_payroll_component_authority('Edit', v_component.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not author a version of component %', p_actor_auth_user_id, p_component_id
      using errcode = 'insufficient_privilege';
  end if;
  if p_calculation_method not in ('fixed_amount', 'hourly_rate', 'percentage_of_component', 'manual_per_run') then
    raise exception 'invalid_calculation_method: %', p_calculation_method using errcode = 'check_violation';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.payroll_component_versions where component_id = p_component_id;

  insert into app.payroll_component_versions (
    component_id, tenant_id, version_number, calculation_method, fixed_amount, percentage_rate,
    percentage_of_component_id, currency, effective_from, is_example_fixture, created_by
  ) values (
    p_component_id, v_component.tenant_id, v_next_version, p_calculation_method, p_fixed_amount, p_percentage_rate,
    p_percentage_of_component_id, coalesce(p_currency, 'IDR'), p_effective_from, false, p_actor_label
  )
  returning * into v_version;

  perform app.capture_audit_event(
    v_component.tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_component_version',
    'app.payroll_component_versions', v_version.id, 'success', null, null, jsonb_build_object('component_id', p_component_id, 'version_number', v_next_version)
  );

  return v_version;
end;
$$;

comment on function app.create_payroll_component_version is
  'HRT-282 (decisions 3, 8): every user-created draft has is_example_fixture=false unconditionally -- only this migration''s own seed INSERT ever sets it true. calculation_method is bounded to the three supported methods (decision 8) -- no free-text formula evaluator exists anywhere in this capability.';

create function app.attach_payroll_component_version_evidence(
  p_version_id uuid, p_expected_version integer, p_sme_evidence_reference text, p_sme_evidence_date date, p_sme_evidence_note text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_component_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.payroll_component_versions;
begin
  select * into v_version from app.payroll_component_versions where id = p_version_id for update;
  if not found then
    raise exception 'payroll_component_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app._check_payroll_component_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not edit component version %', p_actor_auth_user_id, p_version_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'payroll_component_version_not_draft: % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if p_sme_evidence_reference is null or length(trim(p_sme_evidence_reference)) = 0 or p_sme_evidence_date is null then
    raise exception 'sme_evidence_missing: a non-empty evidence reference and a dated evidence date are both required' using errcode = 'check_violation';
  end if;

  update app.payroll_component_versions
  set sme_evidence_reference = p_sme_evidence_reference, sme_evidence_date = p_sme_evidence_date, sme_evidence_note = p_sme_evidence_note
  where id = p_version_id
  returning * into v_version;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'attach_payroll_component_version_evidence',
    'app.payroll_component_versions', v_version.id, 'success', null, null, jsonb_build_object('sme_evidence_reference', v_version.sme_evidence_reference)
  );

  return v_version;
end;
$$;

comment on function app.attach_payroll_component_version_evidence is
  'HRT-282 (decision 3, RPD-016): mirrors app.attach_finance_tax_rule_evidence (FIN-195) exactly -- a reference PLUS a dated evidence date are both required (stricter than Finance''s own "file or note" either/or, since RPD-016 explicitly requires a CURRENT DATED evidence trail). Required before app.approve_payroll_component_version will activate a statutory component.';

create function app.approve_payroll_component_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_component_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.payroll_component_versions;
  v_component app.payroll_components;
  v_overlap_count integer;
begin
  select * into v_version from app.payroll_component_versions where id = p_version_id for update;
  if not found then
    raise exception 'payroll_component_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  select * into v_component from app.payroll_components where id = v_version.component_id;

  if not app._check_payroll_component_authority('Approve', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for component version %', p_actor_auth_user_id, p_version_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status <> 'draft' then
    raise exception 'payroll_component_version_not_draft: % is % not draft', p_version_id, v_version.status using errcode = 'check_violation';
  end if;
  if v_version.is_example_fixture then
    raise exception 'payroll_component_version_example_fixture_not_activatable: version % is a seeded illustrative example and can never be approved -- create a fresh evidence-backed draft', p_version_id
      using errcode = 'check_violation';
  end if;
  if v_component.is_statutory and (v_version.sme_evidence_reference is null or v_version.sme_evidence_date is null) then
    raise exception 'sme_evidence_missing: statutory component version % has no attached, dated SME evidence (RPD-016)', p_version_id
      using errcode = 'check_violation';
  end if;

  select count(*) into v_overlap_count from app.payroll_component_versions v
    where v.component_id = v_version.component_id and v.status = 'approved' and v.id <> v_version.id
      and v.effective_from <= coalesce(v_version.effective_to, 'infinity'::date)
      and coalesce(v.effective_to, 'infinity'::date) >= v_version.effective_from;
  if v_overlap_count > 0 then
    raise exception 'payroll_component_version_overlap: version % overlaps an already-approved version of the same component', p_version_id
      using errcode = 'check_violation';
  end if;

  update app.payroll_component_versions set status = 'approved', published_by = p_actor_label, published_at = now()
  where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: concurrent update detected for version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_payroll_component_version',
    'app.payroll_component_versions', v_version.id, 'success', null, null, jsonb_build_object('component_id', v_version.component_id)
  );

  return v_version;
end;
$$;

comment on function app.approve_payroll_component_version is
  'HRT-282 (decision 3, RPD-016 -- mirrors app.approve_finance_tax_rule, FIN-195, exactly): example-fixture versions can never reach approved; a statutory component additionally requires attached, dated SME evidence. This repository has no such evidence anywhere for Indonesia payroll statutory rules (mandatory reading item 5) -- every seeded statutory component version therefore remains permanently un-approvable until a real SME creates a fresh evidence-backed draft.';

create function app.archive_payroll_component_version(p_version_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_component_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_version app.payroll_component_versions;
begin
  select * into v_version from app.payroll_component_versions where id = p_version_id for update;
  if not found then
    raise exception 'payroll_component_version_not_found: %', p_version_id using errcode = 'no_data_found';
  end if;
  if not app._check_payroll_component_authority('Edit', v_version.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % may not archive component version %', p_actor_auth_user_id, p_version_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_version.status not in ('draft', 'approved') then
    raise exception 'invalid_transition: version % is already %', p_version_id, v_version.status using errcode = 'check_violation';
  end if;

  update app.payroll_component_versions set status = 'archived' where id = p_version_id and record_version = p_expected_version
  returning * into v_version;
  if not found then
    raise exception 'stale_version: concurrent update detected for version %', p_version_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_version.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_payroll_component_version',
    'app.payroll_component_versions', v_version.id, 'success', null, null, null
  );

  return v_version;
end;
$$;

create function app.resolve_effective_payroll_component_version(p_component_id uuid, p_as_of_date date)
returns setof app.payroll_component_versions
language sql
stable
as $$
  select * from app.payroll_component_versions
  where component_id = p_component_id and status = 'approved'
    and effective_from <= p_as_of_date and coalesce(effective_to, 'infinity'::date) >= p_as_of_date
  order by effective_from desc
  limit 1;
$$;

comment on function app.resolve_effective_payroll_component_version is
  'HRT-282: latest-effective-approved-version resolution, mirrors app.resolve_effective_attendance_policy_version (HRT-278). Returns zero rows for a component with no approved version -- e.g. every seeded statutory component until an SME activates one (decision 3) -- app.calculate_payroll_run treats this as "component not currently active", never an error, and simply excludes it from that run.';

-- ===========================================================================
-- 16. Employee component assignment.
-- ===========================================================================

create function app.assign_payroll_component_to_employee(
  p_tenant_id uuid, p_employee_id uuid, p_component_id uuid, p_override_amount numeric, p_override_percentage numeric,
  p_manual_amount numeric, p_currency text, p_effective_from date, p_effective_to date,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_employee_component_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_component app.payroll_components;
  v_assignment app.payroll_employee_component_assignments;
begin
  if not app.check_payroll_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'employee_not_found: % is not a known employee for tenant %', p_employee_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  select * into v_component from app.payroll_components where id = p_component_id and (tenant_id = p_tenant_id or tenant_id is null) and status = 'active';
  if not found then
    raise exception 'payroll_component_not_found: % is not an active component visible to tenant %', p_component_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.payroll_employee_component_assignments (
      tenant_id, employee_id, component_id, override_amount, override_percentage, manual_amount, currency, effective_from, effective_to, created_by
    ) values (
      p_tenant_id, p_employee_id, p_component_id, p_override_amount, p_override_percentage, p_manual_amount,
      coalesce(p_currency, 'IDR'), p_effective_from, p_effective_to, p_actor_label
    )
    returning * into v_assignment;
  exception
    when exclusion_violation then
      raise exception 'payroll_assignment_overlap: employee % already has an active assignment of component % overlapping this date range', p_employee_id, p_component_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'assign_payroll_component_to_employee',
    'app.payroll_employee_component_assignments', v_assignment.id, 'success', null, null,
    jsonb_build_object('employee_id', p_employee_id, 'component_id', p_component_id)
  );

  return v_assignment;
end;
$$;

create function app.end_payroll_component_assignment(p_assignment_id uuid, p_expected_version integer, p_effective_to date, p_end_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_employee_component_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assignment app.payroll_employee_component_assignments;
begin
  select * into v_assignment from app.payroll_employee_component_assignments where id = p_assignment_id for update;
  if not found then
    raise exception 'payroll_assignment_not_found: %', p_assignment_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_assignment.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_assignment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_assignment.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_assignment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_assignment.status <> 'active' then
    raise exception 'invalid_transition: assignment % is already %', p_assignment_id, v_assignment.status using errcode = 'check_violation';
  end if;
  if p_end_reason is null or length(trim(p_end_reason)) = 0 then
    raise exception 'reason_required: a reason is required to end an assignment' using errcode = 'check_violation';
  end if;

  update app.payroll_employee_component_assignments
  set status = 'ended', effective_to = coalesce(p_effective_to, current_date), end_reason = p_end_reason
  where id = p_assignment_id and record_version = p_expected_version
  returning * into v_assignment;
  if not found then
    raise exception 'stale_version: concurrent update detected for assignment %', p_assignment_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_assignment.tenant_id, p_actor_auth_user_id, p_actor_label, 'end_payroll_component_assignment',
    'app.payroll_employee_component_assignments', v_assignment.id, 'success', p_end_reason, null, null
  );

  return v_assignment;
end;
$$;

-- ===========================================================================
-- 17. Reimbursement request lifecycle (decisions 6, 9).
-- ===========================================================================

create function app._create_payroll_reimbursement_request(
  p_tenant_id uuid, p_employee_id uuid, p_category text, p_amount numeric, p_currency text, p_expense_date date,
  p_description text, p_evidence_file_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_existing app.payroll_reimbursement_requests;
  v_request app.payroll_reimbursement_requests;
  v_file app.files;
begin
  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id;
  if not found or v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_employee_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_amount: amount must be positive' using errcode = 'check_violation';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'description_required: a non-empty description is required' using errcode = 'check_violation';
  end if;
  if p_evidence_file_id is not null then
    -- Taxonomy C-10: re-validate tenant/record scope/scan status at THIS
    -- accepting RPC, never trust the caller's own upload-time classification.
    select * into v_file from app.files where id = p_evidence_file_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'evidence_file_not_found: % is not a known file for tenant %', p_evidence_file_id, p_tenant_id using errcode = 'no_data_found';
    end if;
    if v_file.malware_scan_status <> 'clean' then
      raise exception 'evidence_file_not_clean: % has not passed malware scanning', p_evidence_file_id using errcode = 'check_violation';
    end if;
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.payroll_reimbursement_requests
      where tenant_id = p_tenant_id and employee_id = p_employee_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.category = p_category and v_existing.amount = p_amount and v_existing.expense_date = p_expense_date and v_existing.description = p_description then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different reimbursement request', p_idempotency_key using errcode = 'check_violation';
    end if;
  end if;

  insert into app.payroll_reimbursement_requests (
    tenant_id, employee_id, category, amount, currency, expense_date, description, evidence_file_id,
    requested_by_auth_user_id, requested_by, idempotency_key, created_by
  ) values (
    p_tenant_id, p_employee_id, p_category, p_amount, coalesce(p_currency, 'IDR'), p_expense_date, p_description, p_evidence_file_id,
    p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
  )
  returning * into v_request;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_reimbursement_request',
    'app.payroll_reimbursement_requests', v_request.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'amount', p_amount)
  );

  return v_request;
end;
$$;

create function app.create_payroll_reimbursement_request(
  p_tenant_id uuid, p_category text, p_amount numeric, p_currency text, p_expense_date date, p_description text,
  p_evidence_file_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    raise exception 'employee_not_found: no employee record linked to this identity' using errcode = 'no_data_found';
  end if;
  return app._create_payroll_reimbursement_request(
    p_tenant_id, v_self.master_record_id, p_category, p_amount, p_currency, p_expense_date, p_description, p_evidence_file_id,
    p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.create_payroll_reimbursement_request is
  'HRT-282: self-service create -- resolves the caller''s own employee_id server-side via app.get_self_employee, no employee_id parameter to spoof (mirrors HRT-281''s own decision 5 exactly).';

create function app.create_payroll_reimbursement_request_for_employee(
  p_tenant_id uuid, p_employee_id uuid, p_category text, p_amount numeric, p_currency text, p_expense_date date, p_description text,
  p_evidence_file_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_payroll_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  return app._create_payroll_reimbursement_request(
    p_tenant_id, p_employee_id, p_category, p_amount, p_currency, p_expense_date, p_description, p_evidence_file_id,
    p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.create_payroll_reimbursement_request_for_employee is
  'HRT-282: HR-on-behalf create, requires HRS:Edit and an explicit employee_id -- distinct entrypoint from the self-service one, matching HRT-281''s createXForEmployee shape.';

create function app.submit_payroll_reimbursement_request(p_request_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.payroll_reimbursement_requests;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_request from app.payroll_reimbursement_requests where id = p_request_id for update;
  if not found then
    raise exception 'payroll_reimbursement_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  if not (v_self.master_record_id = v_request.employee_id or app.check_payroll_authority('Edit', v_request.tenant_id, p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % may not submit this reimbursement request', p_actor_auth_user_id using errcode = 'insufficient_privilege';
  end if;
  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'draft' then
    raise exception 'invalid_transition: request % is % not draft', p_request_id, v_request.status using errcode = 'check_violation';
  end if;

  update app.payroll_reimbursement_requests set status = 'pending_approval' where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: concurrent update detected for request %', p_request_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_payroll_reimbursement_request',
    'app.payroll_reimbursement_requests', v_request.id, 'success', null, null, null
  );

  return v_request;
end;
$$;

create function app.decide_payroll_reimbursement_request(p_request_id uuid, p_expected_version integer, p_decision text, p_decided_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.payroll_reimbursement_requests;
begin
  select * into v_request from app.payroll_reimbursement_requests where id = p_request_id for update;
  if not found then
    raise exception 'payroll_reimbursement_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Approve', v_request.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_request.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  -- Taxonomy C-18: self-approval blocked structurally, not merely by
  -- convention -- the requester can never decide their own request even
  -- while separately holding HRS:Approve.
  if v_request.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_permitted: an actor may not decide their own reimbursement request' using errcode = 'insufficient_privilege';
  end if;
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid_decision: % must be approve or reject', p_decision using errcode = 'check_violation';
  end if;
  if p_decided_reason is null or length(trim(p_decided_reason)) = 0 then
    raise exception 'reason_required: a reason is required to decide a reimbursement request' using errcode = 'check_violation';
  end if;
  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status <> 'pending_approval' then
    raise exception 'invalid_transition: request % is % not pending_approval', p_request_id, v_request.status using errcode = 'check_violation';
  end if;

  update app.payroll_reimbursement_requests
  set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
      decided_by = p_actor_label, decided_at = now(), decided_reason = p_decided_reason
  where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: concurrent update detected for request %', p_request_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_payroll_reimbursement_request',
    'app.payroll_reimbursement_requests', v_request.id, 'success', p_decided_reason, null, jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create function app.cancel_payroll_reimbursement_request(p_request_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_request app.payroll_reimbursement_requests;
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_request from app.payroll_reimbursement_requests where id = p_request_id for update;
  if not found then
    raise exception 'payroll_reimbursement_request_not_found: %', p_request_id using errcode = 'no_data_found';
  end if;
  v_self := app.get_self_employee(v_request.tenant_id, p_actor_auth_user_id);
  if not (v_self.master_record_id = v_request.employee_id or app.check_payroll_authority('Edit', v_request.tenant_id, p_actor_auth_user_id)) then
    raise exception 'insufficient_authority: identity % may not cancel this reimbursement request', p_actor_auth_user_id using errcode = 'insufficient_privilege';
  end if;
  if v_request.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_request.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_request.status not in ('draft', 'pending_approval') then
    raise exception 'invalid_transition: request % is % -- only draft/pending_approval may be cancelled', p_request_id, v_request.status
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a reimbursement request' using errcode = 'check_violation';
  end if;

  update app.payroll_reimbursement_requests set status = 'cancelled', cancel_reason = p_reason where id = p_request_id and record_version = p_expected_version
  returning * into v_request;
  if not found then
    raise exception 'stale_version: concurrent update detected for request %', p_request_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_request.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_payroll_reimbursement_request',
    'app.payroll_reimbursement_requests', v_request.id, 'success', p_reason, null, null
  );

  return v_request;
end;
$$;

-- ===========================================================================
-- 18. Loan lifecycle (decisions 9, 13).
-- ===========================================================================

create function app.issue_payroll_loan(
  p_tenant_id uuid, p_employee_id uuid, p_principal_amount numeric, p_currency text, p_installment_amount numeric,
  p_term_count integer, p_is_opening_balance boolean, p_opening_remaining_installments integer, p_notes text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.payroll_loans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_employee app.employees;
  v_loan app.payroll_loans;
  v_remaining integer;
  i integer;
begin
  if not app.check_payroll_authority('Approve', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_employee from app.employees where master_record_id = p_employee_id and tenant_id = p_tenant_id;
  if not found or v_employee.lifecycle_status in ('terminated', 'archived') then
    raise exception 'employee_not_active: % is not an active employee for tenant %', p_employee_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if p_principal_amount is null or p_principal_amount <= 0 or p_installment_amount is null or p_installment_amount <= 0 or p_term_count is null or p_term_count <= 0 then
    raise exception 'invalid_loan_terms: principal, installment amount and term count must all be positive' using errcode = 'check_violation';
  end if;

  v_remaining := case when coalesce(p_is_opening_balance, false) then coalesce(p_opening_remaining_installments, p_term_count) else p_term_count end;
  if v_remaining < 0 or v_remaining > p_term_count then
    raise exception 'invalid_opening_remaining_installments: % must be between 0 and term_count %', v_remaining, p_term_count using errcode = 'check_violation';
  end if;

  insert into app.payroll_loans (
    tenant_id, employee_id, principal_amount, currency, installment_amount, term_count, remaining_installments,
    is_opening_balance, notes, issued_by, created_by
  ) values (
    p_tenant_id, p_employee_id, p_principal_amount, coalesce(p_currency, 'IDR'), p_installment_amount, p_term_count, v_remaining,
    coalesce(p_is_opening_balance, false), p_notes, p_actor_label, p_actor_label
  )
  returning * into v_loan;

  for i in (p_term_count - v_remaining + 1) .. p_term_count loop
    insert into app.payroll_loan_installments (loan_id, tenant_id, installment_number, amount)
    values (v_loan.id, p_tenant_id, i, p_installment_amount);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'issue_payroll_loan',
    'app.payroll_loans', v_loan.id, 'success', null, null, jsonb_build_object('employee_id', p_employee_id, 'principal_amount', p_principal_amount)
  );

  return v_loan;
end;
$$;

comment on function app.issue_payroll_loan is
  'HRT-282 (decision 13): p_is_opening_balance=true is the disclosed, bounded cutover path -- only the REMAINING installments (p_opening_remaining_installments) are scheduled, numbered from (term_count - remaining + 1) so a run''s own "next scheduled installment" resolution stays a simple ascending scan regardless of whether the loan started fresh or mid-repayment.';

create function app.cancel_payroll_loan(p_loan_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_loans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_loan app.payroll_loans;
begin
  select * into v_loan from app.payroll_loans where id = p_loan_id for update;
  if not found then
    raise exception 'payroll_loan_not_found: %', p_loan_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Approve', v_loan.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_loan.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_loan.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_loan.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_loan.status <> 'active' then
    raise exception 'invalid_transition: loan % is already %', p_loan_id, v_loan.status using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a loan' using errcode = 'check_violation';
  end if;

  update app.payroll_loans set status = 'cancelled', cancel_reason = p_reason where id = p_loan_id and record_version = p_expected_version
  returning * into v_loan;
  if not found then
    raise exception 'stale_version: concurrent update detected for loan %', p_loan_id using errcode = 'serialization_failure';
  end if;

  update app.payroll_loan_installments set status = 'waived' where loan_id = p_loan_id and status = 'scheduled';

  perform app.capture_audit_event(
    v_loan.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_payroll_loan',
    'app.payroll_loans', v_loan.id, 'success', p_reason, null, null
  );

  return v_loan;
end;
$$;

-- ===========================================================================
-- 19. app.payroll_runs lifecycle: create / calculate / exceptions /
--     submit-for-finalization / finalize / cancel (decisions 6, 8, 9, 10, 11).
-- ===========================================================================

create function app.create_payroll_run(p_tenant_id uuid, p_period_id uuid, p_run_type text, p_adjusts_run_id uuid, p_currency text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
  v_adjusted app.payroll_runs;
  v_existing app.payroll_runs;
  v_run app.payroll_runs;
begin
  if not app.check_payroll_authority('Edit', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  select * into v_period from app.payroll_periods where id = p_period_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'payroll_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  if p_run_type not in ('regular', 'off_cycle', 'correction', 'adjustment') then
    raise exception 'invalid_run_type: %', p_run_type using errcode = 'check_violation';
  end if;
  if p_run_type = 'regular' and v_period.status = 'open' then
    raise exception 'payroll_period_inputs_not_frozen: period % has not had its inputs frozen yet', p_period_id using errcode = 'check_violation';
  end if;
  if p_run_type in ('correction', 'adjustment') then
    if p_adjusts_run_id is null then
      raise exception 'adjusts_run_id_required: % runs must reference the run they correct', p_run_type using errcode = 'check_violation';
    end if;
    select * into v_adjusted from app.payroll_runs where id = p_adjusts_run_id and tenant_id = p_tenant_id;
    if not found or v_adjusted.status <> 'finalized' then
      raise exception 'payroll_run_adjust_target_not_finalized: % is not a finalized run for tenant %', p_adjusts_run_id, p_tenant_id using errcode = 'check_violation';
    end if;
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.payroll_runs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.payroll_period_id = p_period_id and v_existing.run_type = p_run_type and v_existing.adjusts_run_id is not distinct from p_adjusts_run_id then
        return v_existing;
      end if;
      raise exception 'idempotency_key_conflict: key % was already used for a different payroll run', p_idempotency_key using errcode = 'check_violation';
    end if;
  end if;

  begin
    insert into app.payroll_runs (tenant_id, payroll_period_id, run_type, adjusts_run_id, currency, idempotency_key, created_by)
    values (p_tenant_id, p_period_id, p_run_type, p_adjusts_run_id, coalesce(p_currency, 'IDR'), p_idempotency_key, p_actor_label)
    returning * into v_run;
  exception
    when unique_violation then
      raise exception 'payroll_run_already_active: an active regular run already exists for period %', p_period_id using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_payroll_run',
    'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('period_id', p_period_id, 'run_type', p_run_type)
  );

  return v_run;
end;
$$;

-- The batch/chunk calculation engine (Prompt 282 sections 17/28 -- reuses
-- PLT-131/132's own app.jobs framework, mandatory reading item 9, never a
-- second queue mechanism). Processes employees in chunks, heartbeats the
-- job lease at each chunk boundary (a genuine checkpoint), and honors a
-- concurrent cancellation request mid-run.
create function app.calculate_payroll_run(p_run_id uuid, p_expected_version integer, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
  v_period app.payroll_periods;
  v_job app.jobs;
  v_worker_id text;
  v_snapshot app.payroll_input_snapshots;
  v_employee_count integer := 0;
  v_exception_count integer := 0;
  v_chunk_size constant integer := 25;
  v_since_heartbeat integer := 0;
  v_current_job app.jobs;
  v_cancelled boolean := false;
begin
  select * into v_run from app.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_run.status not in ('draft', 'calculated', 'exception') then
    raise exception 'invalid_transition: run % is % -- only draft/calculated/exception may (re)calculate', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  select * into v_period from app.payroll_periods where id = v_run.payroll_period_id;
  if v_period.status = 'open' then
    raise exception 'payroll_period_inputs_not_frozen: period % has not had its inputs frozen yet', v_period.id using errcode = 'check_violation';
  end if;

  v_job := app.enqueue_job(
    v_run.tenant_id, 'payroll_calculation', jsonb_build_object('run_id', p_run_id),
    0, coalesce(p_idempotency_key, 'payroll_calc:' || p_run_id::text || ':' || gen_random_uuid()::text), 3, p_actor_auth_user_id, p_actor_label
  );
  -- C-01: full-tuple idempotency replay check -- a key match must target
  -- THIS run, never merely share a key by coincidence.
  if (v_job.payload ->> 'run_id')::uuid <> p_run_id then
    raise exception 'idempotency_key_conflict: key was already used for a different payroll run' using errcode = 'check_violation';
  end if;
  if v_job.status <> 'pending' then
    -- A genuine replay of an already-processed key -- return the run
    -- unchanged, never recompute a second time under the same key.
    return v_run;
  end if;

  v_worker_id := 'inline-payroll-calc:' || p_actor_auth_user_id::text;
  update app.jobs set status = 'in_progress', locked_by = v_worker_id, locked_until = now() + interval '10 minutes'
  where job_id = v_job.job_id and status = 'pending';

  update app.payroll_runs set status = 'calculating' where id = p_run_id;

  delete from app.payroll_calculation_lines where payroll_run_id = p_run_id;
  delete from app.payroll_run_employee_results where payroll_run_id = p_run_id;
  delete from app.payroll_exceptions where payroll_run_id = p_run_id;

  for v_snapshot in select * from app.payroll_input_snapshots where payroll_period_id = v_run.payroll_period_id order by employee_id loop
    v_since_heartbeat := v_since_heartbeat + 1;
    if v_since_heartbeat >= v_chunk_size then
      -- Checkpoint boundary: extend the lease, and honor a concurrent
      -- cancellation request (app.cancel_import_export_job sets status
      -- 'cancelling' on a job already in_progress).
      select * into v_current_job from app.jobs where job_id = v_job.job_id;
      if v_current_job.status = 'cancelling' then
        v_cancelled := true;
        exit;
      end if;
      perform app.heartbeat_job(v_job.job_id, v_worker_id, 600);
      v_since_heartbeat := 0;
    end if;

    begin
      perform app._calculate_payroll_run_for_employee(v_run, v_period.period_end, v_snapshot, p_actor_label);
      v_employee_count := v_employee_count + 1;
    exception
      when others then
        insert into app.payroll_exceptions (tenant_id, payroll_run_id, employee_id, exception_type, severity, message)
        values (v_run.tenant_id, p_run_id, v_snapshot.employee_id, 'calculation_error', 'high', sqlerrm);
        v_exception_count := v_exception_count + 1;
    end;
  end loop;

  if v_cancelled then
    perform app.acknowledge_job_cancellation(v_job.job_id, p_actor_auth_user_id, p_actor_label);
    update app.payroll_runs set status = 'draft' where id = p_run_id returning * into v_run;
    perform app.capture_audit_event(
      v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_payroll_run_cancelled',
      'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('processed_before_cancel', v_employee_count)
    );
    return v_run;
  end if;

  perform app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

  update app.payroll_runs
  set status = case when v_exception_count > 0 then 'exception' else 'calculated' end,
      employee_count = v_employee_count, exception_count = v_exception_count, calculated_by = p_actor_label, calculated_at = now(), job_id = v_job.job_id
  where id = p_run_id
  returning * into v_run;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_payroll_run',
    'app.payroll_runs', v_run.id, 'success', null, null,
    jsonb_build_object('employee_count', v_employee_count, 'exception_count', v_exception_count)
  );

  return v_run;
end;
$$;

comment on function app.calculate_payroll_run is
  'HRT-282 (sections 17/28): reuses PLT-131/132''s app.jobs framework directly -- app.enqueue_job/app.heartbeat_job/app.complete_job/app.acknowledge_job_cancellation, never a second queue. Chunked at 25 employees per heartbeat/cancellation-check boundary (a genuine checkpoint, not decorative). A single employee''s calculation failure is caught, recorded as a payroll_exceptions row, and does NOT abort the rest of the batch -- the run lands in status=exception for review rather than either silently dropping that employee or failing the whole run. Never callable once a run has reached pending_approval/finalized/cancelled (business rule: finalized history never silently recalculates).';

create function app._calculate_payroll_run_for_employee(p_run app.payroll_runs, p_as_of_date date, p_snapshot app.payroll_input_snapshots, p_actor_label text)
returns void
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_assignment record;
  v_version app.payroll_component_versions;
  v_component app.payroll_components;
  v_amount numeric(14, 2);
  v_pass1 jsonb := '{}'::jsonb;
  v_ref_amount numeric(14, 2);
  v_gross numeric(14, 2) := 0;
  v_deductions numeric(14, 2) := 0;
  v_tax numeric(14, 2) := 0;
  v_benefit numeric(14, 2) := 0;
  v_reimb numeric(14, 2) := 0;
  v_loan_repay numeric(14, 2) := 0;
  v_result_id uuid;
  v_reimb_row app.payroll_reimbursement_requests;
  v_loan_row record;
begin
  -- Pass 1: every non-percentage assignment (fixed_amount / hourly_rate /
  -- manual_per_run) -- these never depend on another component's result.
  for v_assignment in
    select a.*, c.component_type, c.gl_mapping_category, c.code as component_code
    from app.payroll_employee_component_assignments a
    join app.payroll_components c on c.id = a.component_id
    where a.employee_id = p_snapshot.employee_id and a.status = 'active'
      and a.effective_from <= p_as_of_date and coalesce(a.effective_to, 'infinity'::date) >= p_as_of_date
  loop
    select * into v_version from app.resolve_effective_payroll_component_version(v_assignment.component_id, p_as_of_date);
    if not found then
      continue; -- no approved version currently active -- excluded, never an error (decision 3).
    end if;
    if v_version.calculation_method = 'percentage_of_component' then
      continue; -- pass 2
    end if;

    if v_version.calculation_method = 'manual_per_run' then
      v_amount := coalesce(v_assignment.manual_amount, 0);
    elsif v_version.calculation_method = 'hourly_rate' then
      v_amount := round(coalesce(v_assignment.override_amount, v_version.fixed_amount) * (p_snapshot.regular_minutes / 60.0), 2);
    else
      v_amount := coalesce(v_assignment.override_amount, v_version.fixed_amount);
    end if;
    v_amount := greatest(0, coalesce(v_amount, 0));

    insert into app.payroll_calculation_lines (
      tenant_id, payroll_run_id, employee_id, source_type, component_id, component_version_id, line_type,
      quantity, rate, amount, currency, description
    ) values (
      p_run.tenant_id, p_run.id, p_snapshot.employee_id, 'component', v_assignment.component_id, v_version.id, v_assignment.component_type,
      case when v_version.calculation_method = 'hourly_rate' then round(p_snapshot.regular_minutes / 60.0, 2) else null end,
      case when v_version.calculation_method = 'hourly_rate' then coalesce(v_assignment.override_amount, v_version.fixed_amount) else null end,
      v_amount, v_assignment.currency, v_assignment.component_code
    );

    v_pass1 := v_pass1 || jsonb_build_object(v_assignment.component_id::text, v_amount);
    case v_assignment.component_type
      when 'earning' then v_gross := v_gross + v_amount;
      when 'deduction' then v_deductions := v_deductions + v_amount;
      when 'tax' then v_tax := v_tax + v_amount;
      when 'benefit_employer_cost' then v_benefit := v_benefit + v_amount;
      else null;
    end case;
  end loop;

  -- Pass 2: percentage_of_component assignments, resolved against pass 1's
  -- own map. A reference to a component NOT present in pass 1 (e.g. it
  -- points at another percentage_of_component component -- a two-hop
  -- chain, deliberately unsupported, decision 8) is a real, disclosed
  -- exception, never a silent zero.
  for v_assignment in
    select a.*, c.component_type, c.gl_mapping_category, c.code as component_code
    from app.payroll_employee_component_assignments a
    join app.payroll_components c on c.id = a.component_id
    where a.employee_id = p_snapshot.employee_id and a.status = 'active'
      and a.effective_from <= p_as_of_date and coalesce(a.effective_to, 'infinity'::date) >= p_as_of_date
  loop
    select * into v_version from app.resolve_effective_payroll_component_version(v_assignment.component_id, p_as_of_date);
    if not found or v_version.calculation_method <> 'percentage_of_component' then
      continue;
    end if;
    if not (v_pass1 ? v_version.percentage_of_component_id::text) then
      raise exception 'payroll_formula_dependency_unresolved: component % references % which has no resolvable pass-1 amount for this employee', v_assignment.component_id, v_version.percentage_of_component_id;
    end if;
    v_ref_amount := (v_pass1 ->> v_version.percentage_of_component_id::text)::numeric;
    v_amount := greatest(0, round(coalesce(v_assignment.override_percentage, v_version.percentage_rate) / 100.0 * v_ref_amount, 2));

    insert into app.payroll_calculation_lines (
      tenant_id, payroll_run_id, employee_id, source_type, component_id, component_version_id, line_type,
      quantity, rate, amount, currency, description
    ) values (
      p_run.tenant_id, p_run.id, p_snapshot.employee_id, 'component', v_assignment.component_id, v_version.id, v_assignment.component_type,
      null, coalesce(v_assignment.override_percentage, v_version.percentage_rate), v_amount, v_assignment.currency, v_assignment.component_code
    );

    case v_assignment.component_type
      when 'earning' then v_gross := v_gross + v_amount;
      when 'deduction' then v_deductions := v_deductions + v_amount;
      when 'tax' then v_tax := v_tax + v_amount;
      when 'benefit_employer_cost' then v_benefit := v_benefit + v_amount;
      else null;
    end case;
  end loop;

  -- Reimbursements: every approved-but-not-yet-paid request for this
  -- employee is consumed by this run.
  for v_reimb_row in
    select * from app.payroll_reimbursement_requests
    where employee_id = p_snapshot.employee_id and status = 'approved' and applied_payroll_period_id is null
  loop
    insert into app.payroll_calculation_lines (
      tenant_id, payroll_run_id, employee_id, source_type, reimbursement_request_id, line_type, amount, currency, description
    ) values (
      p_run.tenant_id, p_run.id, p_snapshot.employee_id, 'reimbursement', v_reimb_row.id, 'reimbursement', v_reimb_row.amount, v_reimb_row.currency, v_reimb_row.category
    );
    v_reimb := v_reimb + v_reimb_row.amount;
    update app.payroll_reimbursement_requests set status = 'paid', applied_payroll_period_id = p_run.payroll_period_id where id = v_reimb_row.id;
  end loop;

  -- Loan installments: the NEXT scheduled, undeducted installment for
  -- every active loan.
  for v_loan_row in
    select li.* from app.payroll_loan_installments li
    join app.payroll_loans l on l.id = li.loan_id
    where l.employee_id = p_snapshot.employee_id and l.status = 'active' and li.status = 'scheduled'
      and li.installment_number = (select min(installment_number) from app.payroll_loan_installments where loan_id = li.loan_id and status = 'scheduled')
  loop
    insert into app.payroll_calculation_lines (
      tenant_id, payroll_run_id, employee_id, source_type, loan_installment_id, line_type, amount, currency, description
    ) values (
      p_run.tenant_id, p_run.id, p_snapshot.employee_id, 'loan_installment', v_loan_row.id, 'loan_repayment', v_loan_row.amount, p_run.currency, 'loan_installment_' || v_loan_row.installment_number::text
    );
    v_loan_repay := v_loan_repay + v_loan_row.amount;
    update app.payroll_loan_installments set status = 'deducted', payroll_period_id = p_run.payroll_period_id, deducted_at = now() where id = v_loan_row.id;
    update app.payroll_loans set remaining_installments = remaining_installments - 1,
      status = case when remaining_installments - 1 <= 0 then 'completed' else 'active' end
      where id = v_loan_row.loan_id;
  end loop;

  insert into app.payroll_run_employee_results (
    tenant_id, payroll_run_id, employee_id, input_snapshot_id, currency, gross_earnings, total_deductions, total_tax,
    total_benefit_employer_cost, total_reimbursement, total_loan_repayment, net_pay
  ) values (
    p_run.tenant_id, p_run.id, p_snapshot.employee_id, p_snapshot.id, p_run.currency, v_gross, v_deductions, v_tax,
    v_benefit, v_reimb, v_loan_repay, greatest(0, round(v_gross - v_deductions - v_tax - v_loan_repay + v_reimb, 2))
  )
  returning id into v_result_id;

  if (v_gross - v_deductions - v_tax - v_loan_repay + v_reimb) < 0 then
    insert into app.payroll_exceptions (tenant_id, payroll_run_id, employee_id, exception_type, severity, message)
    values (p_run.tenant_id, p_run.id, p_snapshot.employee_id, 'negative_net_pay', 'high',
      format('computed net pay would be negative (%s) before flooring to zero', round(v_gross - v_deductions - v_tax - v_loan_repay + v_reimb, 2)));
  end if;
end;
$$;

comment on function app._calculate_payroll_run_for_employee is
  'HRT-282 (decisions 8, 9, 10): the per-employee calculation core. Two-pass component resolution (fixed/hourly/manual first, percentage-of-component second, decision 8''s own disclosed single-hop bound); reimbursement/loan-installment consumption (decision 9); net_pay formula (decision 10). A negative pre-floor net pay is floored to 0 AND raises a payroll_exceptions row -- never silently absorbed. service_role only.';

-- ===========================================================================
-- 20. Exception review.
-- ===========================================================================

create function app.resolve_payroll_exception(p_exception_id uuid, p_resolution_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.payroll_exceptions;
begin
  select * into v_exception from app.payroll_exceptions where id = p_exception_id for update;
  if not found then
    raise exception 'payroll_exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_exception.status <> 'open' then
    raise exception 'invalid_transition: exception % is already %', p_exception_id, v_exception.status using errcode = 'check_violation';
  end if;
  if p_resolution_note is null or length(trim(p_resolution_note)) = 0 then
    raise exception 'reason_required: a resolution note is required' using errcode = 'check_violation';
  end if;

  update app.payroll_exceptions set status = 'resolved', resolved_by = p_actor_label, resolved_at = now(), resolution_note = p_resolution_note
  where id = p_exception_id
  returning * into v_exception;

  update app.payroll_runs set exception_count = greatest(0, exception_count - 1) where id = v_exception.payroll_run_id;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'resolve_payroll_exception',
    'app.payroll_exceptions', v_exception.id, 'success', p_resolution_note, null, null
  );

  return v_exception;
end;
$$;

create function app.waive_payroll_exception(p_exception_id uuid, p_resolution_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_exception app.payroll_exceptions;
begin
  select * into v_exception from app.payroll_exceptions where id = p_exception_id for update;
  if not found then
    raise exception 'payroll_exception_not_found: %', p_exception_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Override', v_exception.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Override for tenant %', p_actor_auth_user_id, v_exception.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_exception.status <> 'open' then
    raise exception 'invalid_transition: exception % is already %', p_exception_id, v_exception.status using errcode = 'check_violation';
  end if;
  if p_resolution_note is null or length(trim(p_resolution_note)) = 0 then
    raise exception 'reason_required: a resolution note is required to waive an exception' using errcode = 'check_violation';
  end if;

  update app.payroll_exceptions set status = 'waived', resolved_by = p_actor_label, resolved_at = now(), resolution_note = p_resolution_note
  where id = p_exception_id
  returning * into v_exception;

  update app.payroll_runs set exception_count = greatest(0, exception_count - 1) where id = v_exception.payroll_run_id;

  perform app.capture_audit_event(
    v_exception.tenant_id, p_actor_auth_user_id, p_actor_label, 'waive_payroll_exception',
    'app.payroll_exceptions', v_exception.id, 'success', p_resolution_note, null, null
  );

  return v_exception;
end;
$$;

comment on function app.waive_payroll_exception is
  'HRT-282: HRS:Override-gated (distinct from HRS:Edit-gated resolve, taxonomy C-18 blast-radius matching) -- an explicit, audited acceptance of an unresolved finding, never a silent bypass.';

-- ===========================================================================
-- 21. Maker-checker finalization via PLT-123 (decision 6, mandatory
--     reading item 4, RPD-023 disclosure).
-- ===========================================================================

create function app.submit_payroll_run_for_finalization(p_run_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
  v_open_exceptions integer;
  v_version_id uuid;
  v_approval app.approval_requests;
begin
  select * into v_run from app.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Approve', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Approve for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_run.status <> 'calculated' then
    raise exception 'invalid_transition: run % is % -- only a fully calculated run with zero open exceptions may be submitted', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;

  select count(*) into v_open_exceptions from app.payroll_exceptions where payroll_run_id = p_run_id and status = 'open';
  if v_open_exceptions > 0 then
    raise exception 'payroll_run_has_open_exceptions: run % has % unresolved exception(s)', p_run_id, v_open_exceptions using errcode = 'check_violation';
  end if;

  select cv.id into v_version_id from app.config_versions cv
    join app.config_objects co on co.id = cv.config_object_id
    where co.config_type_code = 'approval' and co.tenant_id = v_run.tenant_id and co.scope_level = 'tenant' and cv.status = 'published'
    limit 1;
  if v_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % has no published approval routing definition', v_run.tenant_id
      using errcode = 'check_violation';
  end if;

  v_approval := app.request_approval(v_version_id, v_run.tenant_id, 'payroll_run', p_run_id, 'payroll_run_finalize:' || p_run_id::text, p_actor_auth_user_id, p_actor_label);

  update app.payroll_runs set status = 'pending_approval', approval_request_id = v_approval.id, submitted_by = p_actor_label, submitted_at = now()
  where id = p_run_id and record_version = p_expected_version
  returning * into v_run;
  if not found then
    raise exception 'stale_version: concurrent update detected for run %', p_run_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'submit_payroll_run_for_finalization',
    'app.payroll_runs', v_run.id, 'success', null, null, jsonb_build_object('approval_request_id', v_approval.id)
  );

  return v_run;
end;
$$;

comment on function app.submit_payroll_run_for_finalization is
  'HRT-282 (decision 6): the MAKER step -- HRS:Approve-gated, requires status=calculated with zero open exceptions, routes through PLT-123 app.request_approval exactly like app.submit_leave_request (HRT-280), raising the SAME approval_definition_not_configured error when the tenant has no published approval routing.';

create function app.finalize_payroll_run(p_request_step_id uuid, p_decision text, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_step app.approval_request_steps;
  v_approval_request app.approval_requests;
  v_updated_request app.approval_requests;
  v_run app.payroll_runs;
  v_period app.payroll_periods;
  v_result app.payroll_run_employee_results;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  select * into v_step from app.approval_request_steps where id = p_request_step_id;
  if not found then
    raise exception 'approval_step_not_found: no approval request step %', p_request_step_id using errcode = 'no_data_found';
  end if;
  select * into v_approval_request from app.approval_requests where id = v_step.request_id;
  if v_approval_request.entity_type <> 'payroll_run' or v_approval_request.entity_id is null then
    raise exception 'not_a_payroll_run_approval: approval request % is not a payroll run finalization approval', v_approval_request.id
      using errcode = 'check_violation';
  end if;

  select * into v_run from app.payroll_runs where id = v_approval_request.entity_id for update;

  -- The REAL authority gate -- PLT-123's own eligible-approver-identity
  -- check AND its own allow_self_approval=false-by-default self-decision
  -- block (decision 6, RPD-023''s disclosed compensating control). Called
  -- BEFORE any payroll-domain-specific logic runs (taxonomy C-05).
  perform app.decide_approval_step(p_request_step_id, p_decision, p_actor_auth_user_id, p_actor_label, p_reason);

  select * into v_updated_request from app.approval_requests where id = v_approval_request.id;

  if v_updated_request.status = 'approved' then
    -- Re-select FOR UPDATE -- taxonomy C-04, the run row must be locked
    -- across the whole decide-then-act window, not merely read once above
    -- before app.decide_approval_step (which itself may have taken time
    -- under contention).
    select * into v_run from app.payroll_runs where id = v_approval_request.entity_id for update;
    if v_run.status <> 'pending_approval' then
      raise exception 'invalid_transition: run % is % -- expected pending_approval', v_run.id, v_run.status using errcode = 'check_violation';
    end if;

    update app.payroll_runs set status = 'finalized', finalized_by = p_actor_label, finalized_at = now() where id = v_run.id
    returning * into v_run;

    if v_run.run_type = 'regular' then
      select * into v_period from app.payroll_periods where id = v_run.payroll_period_id for update;
      update app.payroll_periods set status = 'finalized', finalized_at = now() where id = v_period.id;
    end if;

    for v_result in select * from app.payroll_run_employee_results where payroll_run_id = v_run.id loop
      perform app._generate_payroll_payslip(v_run, v_result, p_actor_label);
    end loop;

    perform app.capture_audit_event(
      v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'finalize_payroll_run',
      'app.payroll_runs', v_run.id, 'success', p_reason, null, jsonb_build_object('status', v_run.status)
    );
  else
    update app.payroll_runs set status = 'calculated', decided_reason = p_reason where id = v_approval_request.entity_id
    returning * into v_run;

    perform app.capture_audit_event(
      v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'finalize_payroll_run_rejected',
      'app.payroll_runs', v_run.id, 'success', p_reason, null, jsonb_build_object('status', v_run.status)
    );
  end if;

  return v_run;
end;
$$;

comment on function app.finalize_payroll_run is
  'HRT-282 (decision 6, mandatory reading item 4): the CHECKER step, mirrors app.decide_leave_request (HRT-280) exactly -- calls app.decide_approval_step FIRST, before any payroll-domain-specific effect, and re-locks the run row FOR UPDATE after that gate clears (taxonomy C-04, defends against a concurrent second finalize attempt racing the SAME approved step). On approve: finalizes the run, locks the period (only for run_type=regular), and generates every employee''s private payslip. On reject: kicks the run back to calculated for correction/resubmission, never a dead end.';

create function app._generate_payroll_payslip(p_run app.payroll_runs, p_result app.payroll_run_employee_results, p_actor_label text)
returns app.payroll_payslips
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_slip app.payroll_payslips;
  v_lines jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'lineType', l.line_type, 'sourceType', l.source_type, 'description', l.description,
    'quantity', l.quantity, 'rate', l.rate, 'amount', l.amount, 'currency', l.currency
  ) order by l.line_type, l.created_at), '[]'::jsonb) into v_lines
  from app.payroll_calculation_lines l
  where l.payroll_run_id = p_run.id and l.employee_id = p_result.employee_id;

  insert into app.payroll_payslips (
    tenant_id, payroll_run_id, payroll_period_id, employee_id, currency, gross_earnings, total_deductions, total_tax,
    total_benefit_employer_cost, total_reimbursement, total_loan_repayment, net_pay, line_items, generated_by
  ) values (
    p_run.tenant_id, p_run.id, p_run.payroll_period_id, p_result.employee_id, p_result.currency, p_result.gross_earnings,
    p_result.total_deductions, p_result.total_tax, p_result.total_benefit_employer_cost, p_result.total_reimbursement,
    p_result.total_loan_repayment, p_result.net_pay, v_lines, p_actor_label
  )
  on conflict (payroll_run_id, employee_id) do nothing
  returning * into v_slip;

  return v_slip;
end;
$$;

comment on function app._generate_payroll_payslip is
  'HRT-282: line_items is built via an explicit jsonb_build_object allowlist (taxonomy C-07) -- never to_jsonb(whole_row); no free-text/PII field beyond the component''s own already-governed code/description is ever copied in. Idempotent (on conflict do nothing) -- a defensive guard, since app.finalize_payroll_run only ever calls this once per (run, employee) by construction. service_role only.';

create function app.cancel_payroll_run(p_run_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
begin
  select * into v_run from app.payroll_runs where id = p_run_id for update;
  if not found then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  if not app.check_payroll_authority('Edit', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks HRS:Edit for tenant %', p_actor_auth_user_id, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_run.record_version <> p_expected_version then
    raise exception 'stale_version: expected version % but current version is %', p_expected_version, v_run.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_run.status not in ('draft', 'calculated', 'exception') then
    raise exception 'invalid_transition: run % is % -- a submitted/finalized run cannot be cancelled directly (reject via app.finalize_payroll_run, or correct via a linked run)', p_run_id, v_run.status
      using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to cancel a payroll run' using errcode = 'check_violation';
  end if;

  update app.payroll_runs set status = 'cancelled', cancel_reason = p_reason where id = p_run_id and record_version = p_expected_version
  returning * into v_run;
  if not found then
    raise exception 'stale_version: concurrent update detected for run %', p_run_id using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_run.tenant_id, p_actor_auth_user_id, p_actor_label, 'cancel_payroll_run',
    'app.payroll_runs', v_run.id, 'success', p_reason, null, null
  );

  return v_run;
end;
$$;

-- ===========================================================================
-- 22. Read RPCs. Every payroll-sensitive read is gated on app.can_view_
--     hris_payroll_row (decision 5) or a direct HRS:View payroll check --
--     never plain HRS:View, never a manager-of-employee predicate.
-- ===========================================================================

create function app.list_payroll_periods(p_tenant_id uuid, p_actor_auth_user_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns setof app.payroll_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.payroll_periods;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  if p_after_id is not null then
    select * into v_after from app.payroll_periods where id = p_after_id;
  end if;
  return query select * from app.payroll_periods
    where tenant_id = p_tenant_id and (p_status is null or status = p_status)
      and (v_after.id is null or period_start < v_after.period_start or (period_start = v_after.period_start and id < v_after.id))
    order by period_start desc, id desc
    limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.get_payroll_period(p_period_id uuid, p_actor_auth_user_id uuid)
returns app.payroll_periods
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_period app.payroll_periods;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_period from app.payroll_periods where id = p_period_id;
  if not found or not app.has_active_tenant_membership(v_period.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_period_not_found: %', p_period_id using errcode = 'no_data_found';
  end if;
  return v_period;
end;
$$;

create function app.list_payroll_components(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_components
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_components where tenant_id = p_tenant_id or tenant_id is null order by code;
end;
$$;

create function app.list_payroll_component_versions(p_component_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_component_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_component app.payroll_components;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  select * into v_component from app.payroll_components where id = p_component_id;
  if not found then
    return;
  end if;
  if v_component.tenant_id is not null and not app.has_active_tenant_membership(v_component.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_component_versions where component_id = p_component_id order by version_number desc;
end;
$$;

create function app.list_payroll_employee_component_assignments(p_tenant_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_employee_component_assignments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.can_view_hris_payroll_row(p_tenant_id, p_employee_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_employee_component_assignments
    where tenant_id = p_tenant_id and employee_id = p_employee_id order by effective_from desc;
end;
$$;

create function app.list_my_payroll_reimbursement_requests(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;
  return query select * from app.payroll_reimbursement_requests
    where tenant_id = p_tenant_id and employee_id = v_self.master_record_id order by created_at desc;
end;
$$;

create function app.list_payroll_reimbursement_requests(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_status text, p_limit integer, p_after_id uuid)
returns setof app.payroll_reimbursement_requests
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_after app.payroll_reimbursement_requests;
begin
  if not app.check_payroll_authority('View payroll', p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  if p_after_id is not null then
    select * into v_after from app.payroll_reimbursement_requests where id = p_after_id;
  end if;
  return query select * from app.payroll_reimbursement_requests
    where tenant_id = p_tenant_id and (p_employee_id is null or employee_id = p_employee_id) and (p_status is null or status = p_status)
      and (v_after.id is null or created_at < v_after.created_at or (created_at = v_after.created_at and id < v_after.id))
    order by created_at desc, id desc
    limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.list_my_payroll_loans(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_loans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;
  return query select * from app.payroll_loans where tenant_id = p_tenant_id and employee_id = v_self.master_record_id order by issued_at desc;
end;
$$;

create function app.list_payroll_loans(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_status text)
returns setof app.payroll_loans
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_payroll_authority('View payroll', p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_loans
    where tenant_id = p_tenant_id and (p_employee_id is null or employee_id = p_employee_id) and (p_status is null or status = p_status)
    order by issued_at desc;
end;
$$;

create function app.list_payroll_runs(p_tenant_id uuid, p_actor_auth_user_id uuid, p_period_id uuid, p_status text)
returns setof app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_payroll_authority('View payroll', p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_runs
    where tenant_id = p_tenant_id and (p_period_id is null or payroll_period_id = p_period_id) and (p_status is null or status = p_status)
    order by created_at desc;
end;
$$;

create function app.get_payroll_run(p_run_id uuid, p_actor_auth_user_id uuid)
returns app.payroll_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
begin
  select * into v_run from app.payroll_runs where id = p_run_id;
  if not found or not app.check_payroll_authority('View payroll', v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'payroll_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;
  return v_run;
end;
$$;

create function app.list_payroll_run_employee_results(p_run_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_run_employee_results
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
begin
  select * into v_run from app.payroll_runs where id = p_run_id;
  if not found or not app.check_payroll_authority('View payroll', v_run.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_run_employee_results where payroll_run_id = p_run_id order by employee_id;
end;
$$;

create function app.list_payroll_calculation_lines(p_run_id uuid, p_employee_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_calculation_lines
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
begin
  select * into v_run from app.payroll_runs where id = p_run_id;
  if not found or not app.can_view_hris_payroll_row(v_run.tenant_id, p_employee_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_calculation_lines where payroll_run_id = p_run_id and employee_id = p_employee_id order by line_type;
end;
$$;

create function app.list_payroll_exceptions(p_run_id uuid, p_status text, p_actor_auth_user_id uuid)
returns setof app.payroll_exceptions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_run app.payroll_runs;
begin
  select * into v_run from app.payroll_runs where id = p_run_id;
  if not found or not app.check_payroll_authority('View payroll', v_run.tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_exceptions where payroll_run_id = p_run_id and (p_status is null or status = p_status) order by severity desc, created_at;
end;
$$;

create function app.list_my_payslips(p_tenant_id uuid, p_actor_auth_user_id uuid)
returns setof app.payroll_payslips
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_self app.employees;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  v_self := app.get_self_employee(p_tenant_id, p_actor_auth_user_id);
  if v_self.master_record_id is null then
    return;
  end if;
  return query select * from app.payroll_payslips where tenant_id = p_tenant_id and employee_id = v_self.master_record_id order by generated_at desc;
end;
$$;

create function app.get_payslip(p_payslip_id uuid, p_actor_auth_user_id uuid)
returns app.payroll_payslips
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_slip app.payroll_payslips;
begin
  select * into v_slip from app.payroll_payslips where id = p_payslip_id;
  if not found or not app.can_view_hris_payroll_row(v_slip.tenant_id, v_slip.employee_id, p_actor_auth_user_id) then
    raise exception 'payslip_not_found: %', p_payslip_id using errcode = 'no_data_found';
  end if;
  return v_slip;
end;
$$;

create function app.list_payslips(p_tenant_id uuid, p_actor_auth_user_id uuid, p_employee_id uuid, p_period_id uuid)
returns setof app.payroll_payslips
language plpgsql
security definer
set search_path = app, pg_temp
as $$
begin
  if not app.check_payroll_authority('View payroll', p_tenant_id, p_actor_auth_user_id) then
    return;
  end if;
  return query select * from app.payroll_payslips
    where tenant_id = p_tenant_id and (p_employee_id is null or employee_id = p_employee_id) and (p_period_id is null or payroll_period_id = p_period_id)
    order by generated_at desc;
end;
$$;

-- ===========================================================================
-- 23. Row-level security. Hardened default-deny throughout -- no table below
--     grants a raw SELECT to `authenticated` that is not narrowed by RLS.
-- ===========================================================================

alter table app.payroll_periods enable row level security;
alter table app.payroll_components enable row level security;
alter table app.payroll_component_versions enable row level security;
alter table app.payroll_employee_component_assignments enable row level security;
alter table app.payroll_reimbursement_requests enable row level security;
alter table app.payroll_loans enable row level security;
alter table app.payroll_loan_installments enable row level security;
alter table app.payroll_input_snapshots enable row level security;
alter table app.payroll_runs enable row level security;
alter table app.payroll_calculation_lines enable row level security;
alter table app.payroll_run_employee_results enable row level security;
alter table app.payroll_exceptions enable row level security;
alter table app.payroll_payslips enable row level security;

-- Non-person-scoped, but still compensation-structure-sensitive (rate/
-- amount figures) -- gated on the SAME protected HRS:View payroll bar as
-- every person-scoped table (decision 5's own narrow-visibility philosophy
-- extended uniformly), never plain tenant membership.
create policy payroll_periods_select_scoped on app.payroll_periods
  for select to authenticated
  using (app.is_supreme_admin() or app.check_payroll_authority('View payroll', tenant_id, auth.uid()));

create policy payroll_components_select_scoped on app.payroll_components
  for select to authenticated
  using (
    app.is_supreme_admin()
    -- Platform-wide (tenant_id null) rows are a label/code catalogue only
    -- (no amount lives on app.payroll_components itself, decision 3) --
    -- visible to any active tenant member. The amount-bearing app.
    -- payroll_component_versions row is separately, more narrowly gated
    -- below on HRS:View payroll per tenant.
    or (tenant_id is null and exists (select 1 from app.tenant_user_identities m where m.auth_user_id = auth.uid() and m.status = 'active'))
    or (tenant_id is not null and app.check_payroll_authority('View payroll', tenant_id, auth.uid()))
  );

create policy payroll_component_versions_select_scoped on app.payroll_component_versions
  for select to authenticated
  using (
    app.is_supreme_admin()
    or (tenant_id is null and exists (select 1 from app.tenant_user_identities m where m.auth_user_id = auth.uid() and m.status = 'active'))
    or (tenant_id is not null and app.check_payroll_authority('View payroll', tenant_id, auth.uid()))
  );

-- Person-scoped -- self OR HRS:View payroll specifically (decision 5).
create policy payroll_employee_component_assignments_select_scoped on app.payroll_employee_component_assignments
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid()));

create policy payroll_reimbursement_requests_select_scoped on app.payroll_reimbursement_requests
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid()));

create policy payroll_loans_select_scoped on app.payroll_loans
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid()));

create policy payroll_loan_installments_select_scoped on app.payroll_loan_installments
  for select to authenticated
  using (
    app.is_supreme_admin()
    or exists (select 1 from app.payroll_loans l where l.id = loan_id and app.can_view_hris_payroll_row(l.tenant_id, l.employee_id, auth.uid()))
  );

create policy payroll_input_snapshots_select_scoped on app.payroll_input_snapshots
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid()));

create policy payroll_runs_select_scoped on app.payroll_runs
  for select to authenticated
  using (app.is_supreme_admin() or app.check_payroll_authority('View payroll', tenant_id, auth.uid()));

create policy payroll_calculation_lines_select_scoped on app.payroll_calculation_lines
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid()));

create policy payroll_run_employee_results_select_scoped on app.payroll_run_employee_results
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid()));

create policy payroll_exceptions_select_scoped on app.payroll_exceptions
  for select to authenticated
  using (app.is_supreme_admin() or app.check_payroll_authority('View payroll', tenant_id, auth.uid()));

create policy payroll_payslips_select_scoped on app.payroll_payslips
  for select to authenticated
  using (app.is_supreme_admin() or app.can_view_hris_payroll_row(tenant_id, employee_id, auth.uid()));

comment on policy payroll_periods_select_scoped on app.payroll_periods is
  'HRT-282 (decision 5): unlike every other HRIS capability''s tenant-membership-only policy on its own non-person-scoped metadata tables, Payroll gates even PERIOD METADATA on HRS:View payroll specifically -- a plain tenant member sees nothing about payroll periods at all, since even their existence/status can disclose whether/when a compensation cycle ran.';

-- ===========================================================================
-- 24. Grants. Per ERR-2026-004: explicit REVOKE before any role-specific
--     GRANT below.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on app.payroll_periods to authenticated, service_role;
grant select on app.payroll_components to authenticated, service_role;
grant select on app.payroll_component_versions to authenticated, service_role;
grant select on app.payroll_employee_component_assignments to authenticated, service_role;
grant select on app.payroll_reimbursement_requests to authenticated, service_role;
grant select on app.payroll_loans to authenticated, service_role;
grant select on app.payroll_loan_installments to authenticated, service_role;
grant select on app.payroll_input_snapshots to authenticated, service_role;
grant select on app.payroll_runs to authenticated, service_role;
grant select on app.payroll_calculation_lines to authenticated, service_role;
grant select on app.payroll_run_employee_results to authenticated, service_role;
grant select on app.payroll_exceptions to authenticated, service_role;
grant select on app.payroll_payslips to authenticated, service_role;

grant insert, update, delete on app.payroll_periods to service_role;
grant insert, update, delete on app.payroll_components to service_role;
grant insert, update, delete on app.payroll_component_versions to service_role;
grant insert, update, delete on app.payroll_employee_component_assignments to service_role;
grant insert, update, delete on app.payroll_reimbursement_requests to service_role;
grant insert, update, delete on app.payroll_loans to service_role;
grant insert, update, delete on app.payroll_loan_installments to service_role;
grant insert, update, delete on app.payroll_input_snapshots to service_role;
grant insert, update, delete on app.payroll_runs to service_role;
grant insert, update, delete on app.payroll_calculation_lines to service_role;
grant insert, update, delete on app.payroll_run_employee_results to service_role;
grant insert, update, delete on app.payroll_exceptions to service_role;
grant insert, update, delete on app.payroll_payslips to service_role;

grant execute on function app.touch_payroll_row() to service_role;
grant execute on function app.check_payroll_authority(text, uuid, uuid) to authenticated, service_role;
grant execute on function app.can_view_hris_payroll_row(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app._check_payroll_component_authority(text, uuid, uuid) to service_role;

grant execute on function app.create_payroll_period(uuid, uuid, text, text, date, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.freeze_payroll_period_inputs(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.reopen_payroll_period_inputs(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_payroll_component(uuid, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_payroll_component_version(uuid, text, numeric, numeric, uuid, text, date, uuid, text) to authenticated, service_role;
grant execute on function app.attach_payroll_component_version_evidence(uuid, integer, text, date, text, uuid, text) to authenticated, service_role;
grant execute on function app.approve_payroll_component_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_payroll_component_version(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_effective_payroll_component_version(uuid, date) to authenticated, service_role;

grant execute on function app.assign_payroll_component_to_employee(uuid, uuid, uuid, numeric, numeric, numeric, text, date, date, uuid, text) to authenticated, service_role;
grant execute on function app.end_payroll_component_assignment(uuid, integer, date, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_payroll_reimbursement_request(uuid, text, numeric, text, date, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.create_payroll_reimbursement_request_for_employee(uuid, uuid, text, numeric, text, date, text, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_payroll_reimbursement_request(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_payroll_reimbursement_request(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_payroll_reimbursement_request(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.issue_payroll_loan(uuid, uuid, numeric, text, numeric, integer, boolean, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_payroll_loan(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.create_payroll_run(uuid, uuid, text, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.calculate_payroll_run(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.resolve_payroll_exception(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.waive_payroll_exception(uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.submit_payroll_run_for_finalization(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.finalize_payroll_run(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.cancel_payroll_run(uuid, integer, text, uuid, text) to authenticated, service_role;

grant execute on function app.list_payroll_periods(uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.get_payroll_period(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_components(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_component_versions(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_employee_component_assignments(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_my_payroll_reimbursement_requests(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_reimbursement_requests(uuid, uuid, uuid, text, integer, uuid) to authenticated, service_role;
grant execute on function app.list_my_payroll_loans(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_loans(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.list_payroll_runs(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_payroll_run(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_run_employee_results(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_calculation_lines(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payroll_exceptions(uuid, text, uuid) to authenticated, service_role;
grant execute on function app.list_my_payslips(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_payslip(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_payslips(uuid, uuid, uuid, uuid) to authenticated, service_role;

-- Internal engine functions -- service_role only (called exclusively from
-- inside this migration's own already-authorized SECURITY DEFINER
-- functions, never a direct authenticated entrypoint).
grant execute on function app._resolve_payroll_time_inputs_for_period(uuid, uuid, date, date) to service_role;
grant execute on function app._build_payroll_input_snapshot_for_employee(uuid, uuid, uuid, date, date, text) to service_role;
grant execute on function app._calculate_payroll_run_for_employee(app.payroll_runs, date, app.payroll_input_snapshots, text) to service_role;
grant execute on function app._generate_payroll_payslip(app.payroll_runs, app.payroll_run_employee_results, text) to service_role;
