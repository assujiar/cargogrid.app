-- Procurement capability PRC-264 (Vendor Performance, CG-S11-PRC-015). First prompt of
-- batch 4 (264-265) of the "lanjut sd prompt 265" operator authorization, built directly
-- on the already-COMPLETED batch 3 (261-263: Vendor Contract / Vendor Capacity and
-- Availability / Vendor Assignment) and on the already-VERIFIED PRC-251 (vendor
-- identity/lifecycle), PRC-253 (compliance eligibility), PRC-255/COM-149 (rate
-- versions), and Phase 5 Operations evidence (milestones, resource assignments, claims).
--
-- Source-reconciled vendor KPI scorecards: a versioned KPI catalogue (formula/window/
-- target/weight/band/exclusion), real-evidence metric calculation, a published,
-- versioned scorecard with composite score/band, issue and corrective-action tracking,
-- reason-required maker-checker manual adjustment, and a governed (system-recommends,
-- human-decides) suspension/blacklist/reactivation action wired into the already-
-- VERIFIED PRC-251 vendor lifecycle RPCs -- never a second vendor lifecycle authority.
--
-- ===========================================================================
-- Design decisions, disclosed rather than left implicit
-- ===========================================================================
--
-- 1. **Eleven KPI categories, one fixed built-in calculator per category, selected by
--    `kpi_code` itself** -- `on_time_pickup`, `on_time_delivery`, `acceptance_rate`,
--    `response_time`, `capacity_fulfillment`, `compliance`, `claims_damage`,
--    `rate_competitiveness`, `rate_validity`, `invoice_accuracy`, `service_complaint_sla`.
--    A tenant's own `app.vendor_kpi_definitions` row configures WHICH window/target/
--    weight/band/min-sample-size a category runs with (versioned, snapshotted onto every
--    scorecard line at publish time) -- it never supplies a formula; the formula is a
--    fixed, auditable SQL calculator per category, not a tenant-authored expression
--    (RPD-022 spirit: explainable, not free-form).
-- 2. **`invoice_accuracy` is real, disclosed, deliberately not computed.** Prompt 264's
--    own source note names this KPI's real evidence source as Prompt 265 (Vendor Invoice
--    Matching), which has not been built as of this checkpoint -- `app.finance_vendor_
--    bills`/`app.finance_ap_open_items` (FIN-199/200) hold raw AP data only, never a
--    three-way-match variance. The catalogue carries a real `invoice_accuracy` row
--    (`is_computable=false`, a mandatory `source_note`) so the category is visibly
--    present and explicitly not-yet-sourced, never silently absent (taxonomy C-20/C-23)
--    and never fabricated. `app._calculate_vendor_kpi_metric_value` returns
--    `is_computable=false` unconditionally for this one code, with no query at all.
-- 3. **Cost/rate competitiveness never surfaces a raw currency amount.** Every one of the
--    eleven calculators returns a ratio/percentage/hour/0-100-score value only --
--    `rate_competitiveness` is a market-percentile rank derived from `app.vendor_rate_
--    versions.base_amount` comparisons, never the amount itself; `claims_damage`/
--    `service_complaint_sla` are shipment-count ratios, never a claim reserve amount.
--    This capability therefore never needs PRC:View-cost gating on a computed VALUE --
--    the one thing it DOES gate behind PRC:View cost is the drilldown's own
--    `contributing_source_ids` (which specific shipments/claims/invitations fed a
--    number), the more operationally sensitive "which record" detail, mirroring `app.
--    mask_claim_settlement_readiness_evaluation_amounts`'s own selective-jsonb-key
--    masking shape (never a whole-object strip). Base-table `select` is tenant-RLS-
--    scoped but not column-restricted, matching this exact phase's own established
--    `app.claim_responsibility_reviews` convention (masking enforced at the RPC layer);
--    since no column here is ever raw currency, this is a strictly lower-risk posture
--    than that precedent, not a new gap.
-- 4. **A real dispute mechanism closes Prompt 264 §22's "dispute a source event"
--    alternative flow and §26's "vendor may... dispute allowed own metrics."**
--    `app.vendor_kpi_source_disputes` records a dispute against one contributing source
--    row for one `kpi_code`; every calculator excludes any `upheld` dispute's own
--    `source_id` from its own computation. No vendor-portal identity exists anywhere in
--    this repository (already-accepted PRC-257/258/261/262/263 precedent) -- a dispute
--    is staff-recorded on the vendor's own behalf, exactly like every other vendor-
--    initiated action in this phase.
-- 5. **`app.vendor_assignment_invitations` gains one additive column, `responded_at`.**
--    `acceptance_rate`'s denominator is real and already existed (invitation `status`);
--    `response_time` (time-to-decide) had NO real timestamp to compute from --
--    `updated_at` is overwritten again the moment `confirm_vendor_assignment` advances an
--    accepted invitation to `assigned`, destroying the original accept/decline moment.
--    Rather than approximate from a column that means something else, this migration
--    adds `responded_at timestamptz` (nullable, set once, first-write-wins by construction
--    since both writers only ever fire from `status='invited'`) via `alter table` and
--    hardens `app.accept_vendor_assignment_invitation`/`app.decline_vendor_assignment_
--    invitation` (PRC-263, already-COMPLETED) with `create or replace function` -- never
--    an edit to the already-applied `20260730720000_*.sql` file itself. Historical rows
--    created before this migration have `responded_at is null` and are correctly excluded
--    from `response_time` (never back-filled or guessed) -- Prompt 264 §19's own "do not
--    back-calculate... label partial coverage."
-- 6. **The overall scorecard band uses a fixed, non-versioned threshold set
--    (`{excellent:90, good:75, watch:60}`)**, distinct from each KPI DEFINITION's own
--    versioned, tenant-configurable `band_thresholds` (used for that one metric's own
--    band). A scorecard blends metrics computed under potentially different definition
--    versions over time; keeping the ROLLUP band deterministic and un-versioned avoids a
--    scorecard's own headline band silently drifting as an unrelated KPI definition is
--    edited. Each per-KPI line's own band is fully versioned/snapshotted, satisfying
--    §24's "band... versioned and snapshotted" at the level it actually applies.
-- 7. **Composite score renormalizes weight over computable KPIs only, and both the
--    computable and total defined weight are recorded (`computable_weight_total`/
--    `total_weight_defined`)** -- publishing is blocked (`insufficient_kpi_coverage`)
--    only when NOTHING is computable; partial coverage publishes with the gap disclosed
--    on the row itself, never silently averaged over an assumed-100 denominator (the
--    exact scoring-crash class Prompt 252's own C-15 finding closed for assessment
--    templates, applied here from the first draft).
-- 8. **Manual adjustment mutates the CURRENT published scorecard's rollup in place**
--    (version-guarded, full before/after audit event on both the adjustment row and the
--    scorecard's own `capture_audit_event` call), rather than minting a whole new
--    scorecard version whose only difference is the adjustment -- `app.vendor_kpi_manual_
--    adjustments` itself is the permanent, append-only before/after evidence trail (§18),
--    so a redundant scorecard version would duplicate that evidence without adding any.
--    Self-approval is blocked (`requested_by_auth_user_id <> decided_by_auth_user_id`),
--    the same `app.decide_claim_responsibility` convention this phase already
--    established.
-- 9. **The governed lifecycle action is a strict two-step recommend/decide split, and
--    `decide` is the ONLY path that ever calls PRC-251's real vendor lifecycle RPCs.**
--    `app.evaluate_vendor_lifecycle_recommendation` (PRC:Edit, system-derived from the
--    scorecard's own band by default, or an analyst-supplied override with a mandatory
--    rationale) never itself changes `app.vendor_profiles.lifecycle_status`. `app.decide_
--    vendor_lifecycle_recommendation` (PRC:Override, the same authority `app.suspend_
--    vendor_profile`/`app.blacklist_vendor_profile`/`app.reactivate_vendor_profile`
--    themselves already require of the identical actor -- checked twice by design, once
--    here, once again inside the nested PRC-251 call) is the one human decision point;
--    on `suspend`/`blacklist`/`reactivate` it calls straight through to PRC-251's own
--    unmodified RPC with a reason citing this recommendation's own id, inside the SAME
--    transaction -- if the PRC-251 call raises (e.g. the vendor is already suspended),
--    the whole decision rolls back atomically, never leaving a "decided but not executed"
--    orphan. `none`/`watch` never call PRC-251 at all. This is Prompt 264's own §24
--    "System may recommend; authorized humans decide" literally, and never re-implements
--    vendor lifecycle state a second time (ADR-0020).
--
-- Per ERR-2026-004: explicit `revoke execute on all functions in schema app from public`
-- before final grants, the standing per-migration convention since PLT-118.

-- ===========================================================================
-- 1. app.vendor_kpi_definitions -- versioned KPI catalogue (root+version collapsed in
--    one table, mirroring app.vendor_contracts' own established shape).
-- ===========================================================================

create table app.vendor_kpi_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  kpi_code text not null,
  version_no integer not null default 1,
  status text not null default 'draft',
  name text not null,
  description text,
  measurement_window_days integer not null,
  min_sample_size integer not null default 1,
  target_value numeric not null,
  target_operator text not null,
  weight numeric not null,
  unit text not null,
  band_thresholds jsonb not null default '{"excellent": 90, "good": 75, "watch": 60}'::jsonb,
  exclusion_rules jsonb not null default '{}'::jsonb,
  is_computable boolean not null default true,
  source_note text,
  rounding_scale integer not null default 2,
  supersedes_definition_id uuid references app.vendor_kpi_definitions (id),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_kpi_definitions_kpi_code_check check (kpi_code in (
    'on_time_pickup', 'on_time_delivery', 'acceptance_rate', 'response_time', 'capacity_fulfillment',
    'compliance', 'claims_damage', 'rate_competitiveness', 'rate_validity', 'invoice_accuracy', 'service_complaint_sla'
  )),
  constraint vendor_kpi_definitions_status_check check (status in ('draft', 'published', 'archived')),
  constraint vendor_kpi_definitions_window_check check (measurement_window_days > 0 and measurement_window_days <= 366),
  constraint vendor_kpi_definitions_min_sample_check check (min_sample_size >= 0),
  constraint vendor_kpi_definitions_target_operator_check check (target_operator in ('gte', 'lte')),
  constraint vendor_kpi_definitions_weight_check check (weight > 0 and weight <= 100),
  constraint vendor_kpi_definitions_unit_check check (unit in ('percent', 'hours', 'score', 'count')),
  constraint vendor_kpi_definitions_rounding_scale_check check (rounding_scale >= 0 and rounding_scale <= 6),
  constraint vendor_kpi_definitions_not_self_supersede check (supersedes_definition_id is null or supersedes_definition_id <> id),
  constraint vendor_kpi_definitions_source_note_check check (is_computable or (source_note is not null and length(trim(source_note)) > 0))
);

comment on table app.vendor_kpi_definitions is
  'PRC-264: one row per KPI catalogue entry VERSION; kpi_code is the stable business identity (one of eleven fixed built-in categories -- design note 1). At most one published row per (tenant_id, kpi_code), enforced by vendor_kpi_definitions_active_unique. band_thresholds/exclusion_rules/target/weight/window are all versioned and snapshotted onto every scorecard line at publish time (Prompt 264 §24). is_computable=false + a mandatory source_note is this checkpoint''s own real, disclosed carve-out for invoice_accuracy (design note 2), never a fabricated computation.';

create index vendor_kpi_definitions_tenant_status_idx on app.vendor_kpi_definitions (tenant_id, status);
create unique index vendor_kpi_definitions_number_version_unique on app.vendor_kpi_definitions (tenant_id, kpi_code, version_no);
create unique index vendor_kpi_definitions_active_unique on app.vendor_kpi_definitions (tenant_id, kpi_code) where status = 'published';
create unique index vendor_kpi_definitions_idempotency_key_unique on app.vendor_kpi_definitions (tenant_id, idempotency_key) where idempotency_key is not null;

create function app.validate_vendor_kpi_band_thresholds(p_thresholds jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_excellent numeric;
  v_good numeric;
  v_watch numeric;
begin
  if p_thresholds is null or jsonb_typeof(p_thresholds) <> 'object' then
    return false;
  end if;
  begin
    v_excellent := (p_thresholds ->> 'excellent')::numeric;
    v_good := (p_thresholds ->> 'good')::numeric;
    v_watch := (p_thresholds ->> 'watch')::numeric;
  exception when others then
    return false;
  end;
  if v_excellent is null or v_good is null or v_watch is null then
    return false;
  end if;
  return v_excellent <= 100 and v_watch >= 0 and v_excellent > v_good and v_good > v_watch;
end;
$$;

comment on function app.validate_vendor_kpi_band_thresholds is
  'PRC-264: true only for a well-formed {excellent, good, watch} object with strictly descending numeric thresholds in [0,100] -- enforced structurally via a table CHECK constraint on app.vendor_kpi_definitions, never merely a convention.';

alter table app.vendor_kpi_definitions
  add constraint vendor_kpi_definitions_band_thresholds_check check (app.validate_vendor_kpi_band_thresholds(band_thresholds));

create function app.touch_vendor_performance_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

comment on function app.touch_vendor_performance_row is
  'PRC-264: shared before-update touch trigger for every versioned/mutable table this migration adds -- record_version += 1, updated_at := now(), mirroring app.touch_vendor_contracts_row''s own identical shape.';

create trigger vendor_kpi_definitions_touch_row
  before update on app.vendor_kpi_definitions
  for each row
  execute function app.touch_vendor_performance_row();

-- ===========================================================================
-- 2. app.vendor_kpi_source_disputes -- design note 4.
-- ===========================================================================

create table app.vendor_kpi_source_disputes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  kpi_code text not null,
  source_id uuid not null,
  source_label text,
  reason text not null,
  status text not null default 'pending',
  raised_by_auth_user_id uuid not null,
  raised_by text,
  raised_at timestamptz not null default now(),
  decided_by_auth_user_id uuid,
  decided_by text,
  decided_at timestamptz,
  decision_notes text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_kpi_source_disputes_kpi_code_check check (kpi_code in (
    'on_time_pickup', 'on_time_delivery', 'acceptance_rate', 'response_time', 'capacity_fulfillment',
    'compliance', 'claims_damage', 'rate_competitiveness', 'rate_validity', 'invoice_accuracy', 'service_complaint_sla'
  )),
  constraint vendor_kpi_source_disputes_status_check check (status in ('pending', 'upheld', 'rejected')),
  constraint vendor_kpi_source_disputes_reason_check check (length(trim(reason)) > 0),
  constraint vendor_kpi_source_disputes_decision_shape_check check ((status = 'pending') = (decided_by_auth_user_id is null and decided_at is null)),
  constraint vendor_kpi_source_disputes_decision_notes_check check (status = 'pending' or (decision_notes is not null and length(trim(decision_notes)) > 0))
);

comment on table app.vendor_kpi_source_disputes is
  'PRC-264: a dispute against one contributing source row (source_id, e.g. a milestone_events/vendor_assignment_invitations/vendor_capacity_reservations/claim_case_extensions/vendor_rate_versions id) for one kpi_code. Every calculator in app._calculate_vendor_kpi_metric_value excludes any source_id with an upheld dispute for that same kpi_code from its own computation. No vendor-portal identity exists (design note 4) -- staff-recorded on the vendor''s own behalf.';

create unique index vendor_kpi_source_disputes_pending_unique on app.vendor_kpi_source_disputes (kpi_code, source_id, vendor_master_id) where status = 'pending';
create index vendor_kpi_source_disputes_tenant_vendor_idx on app.vendor_kpi_source_disputes (tenant_id, vendor_master_id, status);
create index vendor_kpi_source_disputes_upheld_lookup_idx on app.vendor_kpi_source_disputes (kpi_code, source_id) where status = 'upheld';

create trigger vendor_kpi_source_disputes_touch_row
  before update on app.vendor_kpi_source_disputes
  for each row
  execute function app.touch_vendor_performance_row();

-- ===========================================================================
-- 3. app.vendor_kpi_measurement_runs.
-- ===========================================================================

create table app.vendor_kpi_measurement_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  window_start timestamptz not null,
  window_end timestamptz not null,
  triggered_by text not null,
  status text not null default 'completed',
  kpi_count integer not null default 0,
  computable_count integer not null default 0,
  source_checkpoint jsonb not null default '{}'::jsonb,
  idempotency_key text,
  created_by text,
  created_at timestamptz not null default now(),
  constraint vendor_kpi_measurement_runs_window_check check (window_end > window_start),
  constraint vendor_kpi_measurement_runs_triggered_by_check check (triggered_by in ('scheduled', 'manual', 'recalculation')),
  constraint vendor_kpi_measurement_runs_status_check check (status in ('completed', 'partial', 'failed')),
  constraint vendor_kpi_measurement_runs_count_check check (kpi_count >= 0 and computable_count >= 0 and computable_count <= kpi_count)
);

comment on table app.vendor_kpi_measurement_runs is
  'PRC-264: one row per app.calculate_vendor_kpi_metrics invocation (Prompt 264 §21 "a scheduled/on-demand job... calculates explainable metrics for a window"). source_checkpoint records a minimized, per-category evidence-scan summary (never a raw row dump) for the reconciliation-checkpoint requirement (§18/§24).';

create unique index vendor_kpi_measurement_runs_idempotency_key_unique on app.vendor_kpi_measurement_runs (tenant_id, idempotency_key) where idempotency_key is not null;
create index vendor_kpi_measurement_runs_tenant_vendor_idx on app.vendor_kpi_measurement_runs (tenant_id, vendor_master_id, window_start desc);

-- ===========================================================================
-- 4. app.vendor_kpi_metric_values -- versioned per (vendor, kpi_code, window).
-- ===========================================================================

create table app.vendor_kpi_metric_values (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  kpi_definition_id uuid not null references app.vendor_kpi_definitions (id),
  kpi_code text not null,
  window_start timestamptz not null,
  window_end timestamptz not null,
  version_no integer not null default 1,
  is_current boolean not null default true,
  run_id uuid not null references app.vendor_kpi_measurement_runs (id),
  raw_numerator numeric,
  raw_denominator numeric,
  sample_size integer not null default 0,
  computed_value numeric,
  normalized_score numeric,
  is_computable boolean not null default false,
  computation_note text,
  excluded_count integer not null default 0,
  source_evidence jsonb not null default '{}'::jsonb,
  supersedes_metric_value_id uuid references app.vendor_kpi_metric_values (id),
  calculated_at timestamptz not null default now(),
  created_by text,
  created_at timestamptz not null default now(),
  constraint vendor_kpi_metric_values_window_check check (window_end > window_start),
  constraint vendor_kpi_metric_values_sample_size_check check (sample_size >= 0),
  constraint vendor_kpi_metric_values_excluded_check check (excluded_count >= 0),
  constraint vendor_kpi_metric_values_normalized_score_check check (normalized_score is null or (normalized_score >= 0 and normalized_score <= 100)),
  constraint vendor_kpi_metric_values_computable_shape_check check (is_computable or normalized_score is null),
  constraint vendor_kpi_metric_values_not_self_supersede check (supersedes_metric_value_id is null or supersedes_metric_value_id <> id)
);

comment on table app.vendor_kpi_metric_values is
  'PRC-264: one CURRENT row per (tenant, vendor, kpi_code, window) -- vendor_kpi_metric_values_current_unique. A recompute that changes nothing (same computed_value/sample_size/is_computable) returns the existing current row unchanged; a genuine change (a late/corrected source event, Prompt 264 §24) supersedes it with a new version_no, never a silent historical rewrite. source_evidence is an allowlisted-key jsonb (never to_jsonb(whole_row)) -- design note 3.';

create unique index vendor_kpi_metric_values_current_unique on app.vendor_kpi_metric_values (tenant_id, vendor_master_id, kpi_code, window_start, window_end) where is_current;
create index vendor_kpi_metric_values_run_idx on app.vendor_kpi_metric_values (run_id);
create index vendor_kpi_metric_values_vendor_window_idx on app.vendor_kpi_metric_values (tenant_id, vendor_master_id, window_start desc);

-- ===========================================================================
-- 5. app.vendor_kpi_scorecards -- versioned per (vendor, window).
-- ===========================================================================

create table app.vendor_kpi_scorecards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  window_start timestamptz not null,
  window_end timestamptz not null,
  version_no integer not null default 1,
  is_current boolean not null default true,
  status text not null default 'published',
  composite_score numeric,
  band text,
  computable_weight_total numeric not null default 0,
  total_weight_defined numeric not null default 0,
  coverage_note text,
  run_id uuid references app.vendor_kpi_measurement_runs (id),
  supersedes_scorecard_id uuid references app.vendor_kpi_scorecards (id),
  published_by_auth_user_id uuid,
  published_by text,
  published_at timestamptz not null default now(),
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_kpi_scorecards_window_check check (window_end > window_start),
  constraint vendor_kpi_scorecards_status_check check (status in ('published', 'superseded')),
  constraint vendor_kpi_scorecards_band_check check (band is null or band in ('excellent', 'good', 'watch', 'poor')),
  constraint vendor_kpi_scorecards_composite_score_check check (composite_score is null or (composite_score >= 0 and composite_score <= 100)),
  constraint vendor_kpi_scorecards_weight_check check (computable_weight_total >= 0 and total_weight_defined >= 0 and computable_weight_total <= total_weight_defined),
  constraint vendor_kpi_scorecards_not_self_supersede check (supersedes_scorecard_id is null or supersedes_scorecard_id <> id)
);

comment on table app.vendor_kpi_scorecards is
  'PRC-264: one CURRENT row per (tenant, vendor, window) -- vendor_kpi_scorecards_current_unique. composite_score is a weight-renormalized average of normalized_score across is_computable lines ONLY (design note 7) -- computable_weight_total/total_weight_defined disclose exactly how much of the catalogue actually contributed, never silently averaged over an assumed-100 denominator. band uses a fixed, non-versioned threshold set (design note 6), distinct from each line''s own versioned band.';

create unique index vendor_kpi_scorecards_current_unique on app.vendor_kpi_scorecards (tenant_id, vendor_master_id, window_start, window_end) where is_current;
create unique index vendor_kpi_scorecards_idempotency_key_unique on app.vendor_kpi_scorecards (tenant_id, idempotency_key) where idempotency_key is not null;
create index vendor_kpi_scorecards_tenant_vendor_idx on app.vendor_kpi_scorecards (tenant_id, vendor_master_id, window_start desc);

create trigger vendor_kpi_scorecards_touch_row
  before update on app.vendor_kpi_scorecards
  for each row
  execute function app.touch_vendor_performance_row();

-- ===========================================================================
-- 6. app.vendor_kpi_scorecard_lines -- immutable-at-publish snapshot per (scorecard, kpi).
-- ===========================================================================

create table app.vendor_kpi_scorecard_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scorecard_id uuid not null references app.vendor_kpi_scorecards (id),
  metric_value_id uuid references app.vendor_kpi_metric_values (id),
  kpi_definition_id uuid not null references app.vendor_kpi_definitions (id),
  kpi_code text not null,
  kpi_name_snapshot text not null,
  weight_snapshot numeric not null,
  target_value_snapshot numeric not null,
  target_operator_snapshot text not null,
  band_thresholds_snapshot jsonb not null,
  computed_value numeric,
  normalized_score numeric,
  band text,
  is_computable boolean not null default false,
  adjusted boolean not null default false,
  record_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_kpi_scorecard_lines_unique unique (scorecard_id, kpi_code),
  constraint vendor_kpi_scorecard_lines_normalized_score_check check (normalized_score is null or (normalized_score >= 0 and normalized_score <= 100)),
  constraint vendor_kpi_scorecard_lines_band_check check (band is null or band in ('excellent', 'good', 'watch', 'poor'))
);

comment on table app.vendor_kpi_scorecard_lines is
  'PRC-264: one row per KPI category considered at publish time (every published definition, whether computable or not) -- the "all required categories covered or explicitly not applicable" acceptance criterion is this table''s own completeness, not an assumption. kpi_name_snapshot/weight_snapshot/target_value_snapshot/target_operator_snapshot/band_thresholds_snapshot freeze the DEFINITION version in effect at publish time (Prompt 264 §24 "versioned and snapshotted") -- later editing app.vendor_kpi_definitions never rewrites a past scorecard line. adjusted=true + the updated normalized_score/band is the ONLY post-publish mutation this table allows, applied exclusively by app.decide_vendor_kpi_manual_adjustment under a record_version guard (design note 8).';

create index vendor_kpi_scorecard_lines_scorecard_idx on app.vendor_kpi_scorecard_lines (scorecard_id);

create trigger vendor_kpi_scorecard_lines_touch_row
  before update on app.vendor_kpi_scorecard_lines
  for each row
  execute function app.touch_vendor_performance_row();

-- ===========================================================================
-- 7. app.vendor_performance_issues / app.vendor_performance_corrective_actions.
-- ===========================================================================

create table app.vendor_performance_issues (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  scorecard_id uuid references app.vendor_kpi_scorecards (id),
  kpi_code text,
  severity text not null,
  title text not null,
  description text,
  status text not null default 'open',
  raised_by_auth_user_id uuid,
  raised_by text,
  raised_at timestamptz not null default now(),
  resolved_by_auth_user_id uuid,
  resolved_by text,
  resolved_at timestamptz,
  resolution_note text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_performance_issues_kpi_code_check check (kpi_code is null or kpi_code in (
    'on_time_pickup', 'on_time_delivery', 'acceptance_rate', 'response_time', 'capacity_fulfillment',
    'compliance', 'claims_damage', 'rate_competitiveness', 'rate_validity', 'invoice_accuracy', 'service_complaint_sla'
  )),
  constraint vendor_performance_issues_severity_check check (severity in ('low', 'medium', 'high', 'critical')),
  constraint vendor_performance_issues_title_check check (length(trim(title)) > 0),
  constraint vendor_performance_issues_status_check check (status in ('open', 'in_progress', 'resolved', 'closed')),
  constraint vendor_performance_issues_resolution_shape_check check (status not in ('resolved', 'closed') or (resolution_note is not null and length(trim(resolution_note)) > 0))
);

comment on table app.vendor_performance_issues is 'PRC-264: an issue raised against a vendor''s performance, optionally tied to a specific scorecard/kpi_code (both nullable -- an issue may also be raised ad hoc, e.g. from a single severe event, not only from a published scorecard).';

create unique index vendor_performance_issues_idempotency_key_unique on app.vendor_performance_issues (tenant_id, idempotency_key) where idempotency_key is not null;
create index vendor_performance_issues_tenant_vendor_idx on app.vendor_performance_issues (tenant_id, vendor_master_id, status);

create trigger vendor_performance_issues_touch_row
  before update on app.vendor_performance_issues
  for each row
  execute function app.touch_vendor_performance_row();

create table app.vendor_performance_corrective_actions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  issue_id uuid not null references app.vendor_performance_issues (id),
  description text not null,
  owner_label text,
  due_date date,
  status text not null default 'open',
  completed_at timestamptz,
  completion_note text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_performance_corrective_actions_description_check check (length(trim(description)) > 0),
  constraint vendor_performance_corrective_actions_status_check check (status in ('open', 'in_progress', 'completed', 'cancelled')),
  constraint vendor_performance_corrective_actions_completed_shape_check check (status <> 'completed' or completed_at is not null)
);

comment on table app.vendor_performance_corrective_actions is 'PRC-264: a corrective action tracked against one issue. "overdue" is deliberately computed at read time (due_date < current_date and status not in (completed, cancelled)), never a stored status a scheduler would need to flip.';

create unique index vendor_performance_corrective_actions_idempotency_key_unique on app.vendor_performance_corrective_actions (tenant_id, idempotency_key) where idempotency_key is not null;
create index vendor_performance_corrective_actions_issue_idx on app.vendor_performance_corrective_actions (issue_id);

create trigger vendor_performance_corrective_actions_touch_row
  before update on app.vendor_performance_corrective_actions
  for each row
  execute function app.touch_vendor_performance_row();

-- ===========================================================================
-- 8. app.vendor_kpi_manual_adjustments -- design note 8.
-- ===========================================================================

create table app.vendor_kpi_manual_adjustments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  scorecard_id uuid not null references app.vendor_kpi_scorecards (id),
  scorecard_line_id uuid not null references app.vendor_kpi_scorecard_lines (id),
  kpi_code text not null,
  original_normalized_score numeric,
  adjusted_normalized_score numeric not null,
  reason text not null,
  requested_by_auth_user_id uuid not null,
  requested_by text,
  requested_at timestamptz not null default now(),
  status text not null default 'pending_approval',
  decided_by_auth_user_id uuid,
  decided_by text,
  decided_at timestamptz,
  decision_notes text,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_kpi_manual_adjustments_reason_check check (length(trim(reason)) > 0),
  constraint vendor_kpi_manual_adjustments_score_check check (adjusted_normalized_score >= 0 and adjusted_normalized_score <= 100),
  constraint vendor_kpi_manual_adjustments_status_check check (status in ('pending_approval', 'approved', 'rejected')),
  constraint vendor_kpi_manual_adjustments_decision_shape_check check ((status = 'pending_approval') = (decided_by_auth_user_id is null and decided_at is null)),
  constraint vendor_kpi_manual_adjustments_decision_notes_check check (status = 'pending_approval' or (decision_notes is not null and length(trim(decision_notes)) > 0))
);

comment on table app.vendor_kpi_manual_adjustments is
  'PRC-264: reason-required, maker-checker-governed manual override of one scorecard line''s own normalized_score (Prompt 264 objective: "manual adjustment with required reason/approval"). Self-approval blocked (requested_by_auth_user_id <> decided_by_auth_user_id) in app.decide_vendor_kpi_manual_adjustment, mirroring app.decide_claim_responsibility''s own established convention. At most one PENDING adjustment per line at a time (vendor_kpi_manual_adjustments_pending_unique).';

create unique index vendor_kpi_manual_adjustments_pending_unique on app.vendor_kpi_manual_adjustments (scorecard_line_id) where status = 'pending_approval';
create unique index vendor_kpi_manual_adjustments_idempotency_key_unique on app.vendor_kpi_manual_adjustments (tenant_id, idempotency_key) where idempotency_key is not null;
create index vendor_kpi_manual_adjustments_scorecard_idx on app.vendor_kpi_manual_adjustments (scorecard_id);

create trigger vendor_kpi_manual_adjustments_touch_row
  before update on app.vendor_kpi_manual_adjustments
  for each row
  execute function app.touch_vendor_performance_row();

-- ===========================================================================
-- 9. app.vendor_lifecycle_recommendations -- design note 9.
-- ===========================================================================

create table app.vendor_lifecycle_recommendations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  vendor_master_id uuid not null references app.vendor_profiles (master_record_id),
  scorecard_id uuid references app.vendor_kpi_scorecards (id),
  recommended_action text not null,
  recommended_rationale text not null,
  recommended_by_auth_user_id uuid,
  recommended_by text,
  recommended_at timestamptz not null default now(),
  status text not null default 'pending',
  decided_action text,
  decided_by_auth_user_id uuid,
  decided_by text,
  decided_at timestamptz,
  decision_notes text,
  evidence_ref text,
  executed boolean not null default false,
  executed_at timestamptz,
  idempotency_key text,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vendor_lifecycle_recommendations_action_check check (recommended_action in ('none', 'watch', 'suspend', 'blacklist', 'reactivate')),
  constraint vendor_lifecycle_recommendations_decided_action_check check (decided_action is null or decided_action in ('none', 'watch', 'suspend', 'blacklist', 'reactivate')),
  constraint vendor_lifecycle_recommendations_rationale_check check (length(trim(recommended_rationale)) > 0),
  constraint vendor_lifecycle_recommendations_status_check check (status in ('pending', 'decided')),
  constraint vendor_lifecycle_recommendations_decision_shape_check check ((status = 'pending') = (decided_action is null and decided_by_auth_user_id is null and decided_at is null)),
  constraint vendor_lifecycle_recommendations_decision_notes_check check (status = 'pending' or (decision_notes is not null and length(trim(decision_notes)) > 0)),
  constraint vendor_lifecycle_recommendations_blacklist_evidence_check check (decided_action is distinct from 'blacklist' or (evidence_ref is not null and length(trim(evidence_ref)) > 0))
);

comment on table app.vendor_lifecycle_recommendations is
  'PRC-264: the governed suspension/blacklist/reactivation surface (Prompt 264 objective). recommended_action is system-derived from the basis scorecard''s own band by default (poor -> suspend, else none) or an analyst-supplied override with its own mandatory rationale -- either way this row alone NEVER changes app.vendor_profiles.lifecycle_status. Only app.decide_vendor_lifecycle_recommendation (PRC:Override, a human) does that, by calling straight through to the unmodified PRC-251 RPCs (design note 9) -- executed/executed_at record whether that real downstream call happened.';

create unique index vendor_lifecycle_recommendations_idempotency_key_unique on app.vendor_lifecycle_recommendations (tenant_id, idempotency_key) where idempotency_key is not null;
create index vendor_lifecycle_recommendations_tenant_vendor_idx on app.vendor_lifecycle_recommendations (tenant_id, vendor_master_id, status);

create trigger vendor_lifecycle_recommendations_touch_row
  before update on app.vendor_lifecycle_recommendations
  for each row
  execute function app.touch_vendor_performance_row();

-- ===========================================================================
-- 10. Harden PRC-263's app.vendor_assignment_invitations -- design note 5. Additive
--     column, then create-or-replace on its own two already-COMPLETED (never applied to
--     a prior VERIFIED release; this same branch) accept/decline functions.
-- ===========================================================================

alter table app.vendor_assignment_invitations add column responded_at timestamptz;

comment on column app.vendor_assignment_invitations.responded_at is
  'PRC-264 (design note 5): set once, by app.accept_vendor_assignment_invitation or app.decline_vendor_assignment_invitation, the moment the vendor''s decision is recorded -- distinct from updated_at, which is overwritten again once a later app.confirm_vendor_assignment/app.reassign_vendor_assignment call advances the row further. Null for every invitation decided before this migration (never back-filled, Prompt 264 §19) and for any invitation never yet decided (invited/expired/cancelled).';

create or replace function app.accept_vendor_assignment_invitation(
  p_invitation_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
begin
  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05 (already hardened by batch 3's own Tier C fix pass, 20260730730000 -- carried
  -- forward here verbatim, never dropped by this create-or-replace): fold "does not
  -- exist" and "exists in a tenant this caller has no membership in" into the SAME
  -- not-found error before evaluate_permission's own insufficient_authority message
  -- (which echoes the real tenant_id) becomes reachable.
  if not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be accepted', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'accepted', responded_at = now() where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'accept_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', null, null, '{}'::jsonb
  );

  return v_invitation;
end;
$$;

comment on function app.accept_vendor_assignment_invitation is 'PRC-263, hardened by batch 3''s own Tier C fix (C-05 not-found fold) and again by PRC-264 (design note 5): now also sets responded_at := now() so app._calculate_vendor_kpi_metric_value(''response_time'') has a real, non-overwritten decision timestamp to compute from. Both prior fixes carried forward verbatim.';

create or replace function app.decline_vendor_assignment_invitation(
  p_invitation_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.vendor_assignment_invitations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_invitation app.vendor_assignment_invitations;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to decline a vendor assignment invitation' using errcode = 'check_violation';
  end if;

  select * into v_invitation from app.vendor_assignment_invitations where id = p_invitation_id;
  if not found then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;
  -- C-05, carried forward from batch 3's own Tier C fix -- see the identical comment
  -- in app.accept_vendor_assignment_invitation above.
  if not app.has_active_tenant_membership(v_invitation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_assignment_invitation_not_found: %', p_invitation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_invitation.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_invitation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_invitation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor assignment invitation % expected version % but found %', p_invitation_id, p_expected_version, v_invitation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_invitation.status <> 'invited' then
    raise exception 'invalid_transition: vendor assignment invitation % is % and cannot be declined', p_invitation_id, v_invitation.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_assignment_invitations set status = 'declined', decline_reason = p_reason, responded_at = now() where id = p_invitation_id and record_version = p_expected_version returning * into v_invitation;
  if not found then
    raise exception 'stale_version: vendor assignment invitation % target row was concurrently modified (expected version %)', p_invitation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_invitation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decline_vendor_assignment_invitation',
    'app.vendor_assignment_invitations', v_invitation.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_invitation;
end;
$$;

comment on function app.decline_vendor_assignment_invitation is 'PRC-263, hardened by batch 3''s own Tier C fix (C-05 not-found fold) and again by PRC-264 (design note 5): now also sets responded_at := now(), the identical hardening applied to app.accept_vendor_assignment_invitation. Both prior fixes carried forward verbatim.';

-- ===========================================================================
-- 11. Scoring helpers.
-- ===========================================================================

create type app.vendor_kpi_calc_result as (
  raw_numerator numeric,
  raw_denominator numeric,
  sample_size integer,
  computed_value numeric,
  is_computable boolean,
  computation_note text,
  source_evidence jsonb,
  excluded_count integer
);

create function app._normalize_vendor_kpi_score(p_computed_value numeric, p_target_value numeric, p_target_operator text)
returns numeric
language plpgsql
immutable
as $$
begin
  if p_computed_value is null or p_target_value is null or p_target_value = 0 then
    return null;
  end if;
  if p_target_operator = 'gte' then
    if p_computed_value >= p_target_value then
      return 100;
    end if;
    return round(greatest(0, least(100, 100.0 * p_computed_value / p_target_value)), 2);
  elsif p_target_operator = 'lte' then
    if p_computed_value <= p_target_value then
      return 100;
    end if;
    return round(greatest(0, least(100, 100.0 * p_target_value / p_computed_value)), 2);
  else
    raise exception 'invalid_target_operator: % is not one of gte/lte', p_target_operator using errcode = 'check_violation';
  end if;
end;
$$;

comment on function app._normalize_vendor_kpi_score is
  'PRC-264: computed_value meeting-or-beating target always scores 100; short of target scales linearly toward 0 (gte) or asymptotically toward 0 as computed_value grows unbounded past target (lte) -- the SAME formula for every KPI category, driven only by each definition''s own versioned target_value/target_operator (design note 1: fixed calculator, tenant-configured target).';

create function app._band_for_score(p_score numeric, p_thresholds jsonb)
returns text
language sql
immutable
as $$
  select case
    when p_score is null then null
    when p_score >= (p_thresholds ->> 'excellent')::numeric then 'excellent'
    when p_score >= (p_thresholds ->> 'good')::numeric then 'good'
    when p_score >= (p_thresholds ->> 'watch')::numeric then 'watch'
    else 'poor'
  end;
$$;

create function app.mask_vendor_kpi_source_evidence(p_evidence jsonb, p_masked boolean)
returns jsonb
language sql
immutable
as $$
  select case when p_masked then p_evidence - 'contributing_source_ids' else p_evidence end;
$$;

comment on function app.mask_vendor_kpi_source_evidence is
  'PRC-264: strips only the contributing_source_ids key (the "which record" detail) for a caller without PRC:View cost -- design note 3. Every other key (counts, rates) stays visible to any PRC:View holder.';

-- ===========================================================================
-- 12. Per-category calculators (internal only -- no grant, dispatched exclusively by
--     app._calculate_vendor_kpi_metric_value below). Every calculator excludes any
--     source_id carrying an upheld dispute for its own kpi_code (design note 4), and
--     returns source_evidence as a small, explicitly allowlisted set of scalar keys plus
--     (when real) a capped contributing_source_ids array -- never a raw row/jsonb dump
--     (taxonomy C-07).
-- ===========================================================================

create function app._calc_vendor_kpi_on_time_pickup(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  select
    count(*) filter (where x.first_pickup_time is not null and x.first_pickup_time <= x.planned_pickup_at),
    count(*) filter (where x.first_pickup_time is not null),
    array_agg(x.id) filter (where x.first_pickup_time is not null)
  into v_num, v_den, v_ids
  from (
    select so.id, so.planned_pickup_at,
      (
        select min(ev.event_time) from app.milestone_events ev
        join app.milestone_codes mc on mc.code = ev.milestone_code
        where ev.shipment_order_id = so.id and mc.category = 'pickup'
          and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'on_time_pickup' and d.source_id = ev.id and d.status = 'upheld')
      ) as first_pickup_time
    from app.shipment_orders so
    join app.resource_assignments ra on ra.shipment_order_id = so.id and ra.role = 'vendor' and ra.resource_id = p_vendor_master_id
    where so.tenant_id = p_tenant_id and so.planned_pickup_at is not null
      and so.planned_pickup_at >= p_window_start and so.planned_pickup_at < p_window_end
  ) x;

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_pickup_evidence: no shipment assigned to this vendor in the window has a recorded pickup-category milestone event' else null end;
  r.source_evidence := jsonb_build_object('assigned_with_evidence', coalesce(v_den, 0), 'on_time', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_on_time_pickup is
  'PRC-264: numerator/denominator over shipments assigned to this vendor (app.resource_assignments, role=vendor, OPS-172/PRC-263 canonical identity) whose planned_pickup_at falls in the window AND which have at least one pickup-category milestone event (app.milestone_events/app.milestone_codes, OPS-173) -- a shipment with no pickup evidence at all is excluded from the denominator (disclosed via computation_note), never counted as either on-time or late.';

create function app._calc_vendor_kpi_on_time_delivery(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  select
    count(*) filter (where x.first_delivery_time is not null and x.first_delivery_time <= x.planned_delivery_at),
    count(*) filter (where x.first_delivery_time is not null),
    array_agg(x.id) filter (where x.first_delivery_time is not null)
  into v_num, v_den, v_ids
  from (
    select so.id, so.planned_delivery_at,
      (
        select min(ev.event_time) from app.milestone_events ev
        join app.milestone_codes mc on mc.code = ev.milestone_code
        where ev.shipment_order_id = so.id and mc.category = 'delivery'
          and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'on_time_delivery' and d.source_id = ev.id and d.status = 'upheld')
      ) as first_delivery_time
    from app.shipment_orders so
    join app.resource_assignments ra on ra.shipment_order_id = so.id and ra.role = 'vendor' and ra.resource_id = p_vendor_master_id
    where so.tenant_id = p_tenant_id and so.planned_delivery_at is not null
      and so.planned_delivery_at >= p_window_start and so.planned_delivery_at < p_window_end
  ) x;

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_delivery_evidence: no shipment assigned to this vendor in the window has a recorded delivery-category milestone event' else null end;
  r.source_evidence := jsonb_build_object('assigned_with_evidence', coalesce(v_den, 0), 'on_time', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_on_time_delivery is 'PRC-264: identical shape to _calc_vendor_kpi_on_time_pickup, sourced from delivery-category milestone events against planned_delivery_at.';

create function app._calc_vendor_kpi_acceptance_rate(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  select
    count(*) filter (where status in ('accepted', 'assigned')),
    count(*) filter (where status in ('accepted', 'assigned', 'declined', 'expired')),
    array_agg(id) filter (where status in ('accepted', 'assigned', 'declined', 'expired'))
  into v_num, v_den, v_ids
  from app.vendor_assignment_invitations vai
  where vai.tenant_id = p_tenant_id and vai.vendor_master_id = p_vendor_master_id
    and vai.created_at >= p_window_start and vai.created_at < p_window_end
    and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'acceptance_rate' and d.source_id = vai.id and d.status = 'upheld');

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_decided_invitations: no vendor assignment invitation for this vendor reached accepted/declined/expired in the window' else null end;
  r.source_evidence := jsonb_build_object('decided', coalesce(v_den, 0), 'accepted', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_acceptance_rate is
  'PRC-264: over app.vendor_assignment_invitations (PRC-263) created in the window -- denominator is every invitation that reached a real decided-or-timed-out state (accepted/assigned/declined/expired); still-invited or cancelled-by-proposer invitations never entered the vendor''s own decision, so they are excluded from both numerator and denominator (design note: acceptance rate measures the VENDOR''s own response, not the proposer''s).';

create function app._calc_vendor_kpi_response_time(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_avg_hours numeric;
  v_sum_hours numeric;
  v_count integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  select
    avg(extract(epoch from (vai.responded_at - vai.created_at)) / 3600.0),
    sum(extract(epoch from (vai.responded_at - vai.created_at)) / 3600.0),
    count(*),
    array_agg(vai.id)
  into v_avg_hours, v_sum_hours, v_count, v_ids
  from app.vendor_assignment_invitations vai
  where vai.tenant_id = p_tenant_id and vai.vendor_master_id = p_vendor_master_id and vai.responded_at is not null
    and vai.created_at >= p_window_start and vai.created_at < p_window_end
    and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'response_time' and d.source_id = vai.id and d.status = 'upheld');

  r.raw_numerator := v_sum_hours;
  r.raw_denominator := v_count;
  r.sample_size := coalesce(v_count, 0);
  r.is_computable := coalesce(v_count, 0) > 0;
  r.computed_value := case when v_count > 0 then round(v_avg_hours, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_responded_invitations: no vendor assignment invitation for this vendor carries a recorded responded_at in the window (design note 5 -- invitations decided before this checkpoint have no responded_at and are correctly excluded, never back-filled)' else null end;
  r.source_evidence := jsonb_build_object('responded_count', coalesce(v_count, 0), 'avg_hours', r.computed_value, 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_response_time is
  'PRC-264: average hours between app.vendor_assignment_invitations.created_at and responded_at (design note 5''s new column -- accept/decline only, never expiry/cancellation, which are not a vendor decision). Lower is better (target_operator=lte).';

create function app._calc_vendor_kpi_capacity_fulfillment(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  select
    count(*) filter (where r2.status = 'consumed'),
    count(*) filter (where r2.status in ('accepted', 'consumed')),
    array_agg(r2.id) filter (where r2.status in ('accepted', 'consumed'))
  into v_num, v_den, v_ids
  from app.vendor_capacity_reservations r2
  join app.vendor_capacity_offers o on o.id = r2.offer_id
  where o.tenant_id = p_tenant_id and o.vendor_master_id = p_vendor_master_id
    and r2.created_at >= p_window_start and r2.created_at < p_window_end
    and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'capacity_fulfillment' and d.source_id = r2.id and d.status = 'upheld');

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_accepted_reservations: no vendor capacity reservation for this vendor was accepted or consumed in the window (a held-only reservation was never a real commitment -- excluded, matching the batch-3 Tier C fix for the SAME held-vs-accepted distinction)' else null end;
  r.source_evidence := jsonb_build_object('committed', coalesce(v_den, 0), 'fulfilled', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_capacity_fulfillment is
  'PRC-264: over app.vendor_capacity_reservations (PRC-262) against this vendor''s own offers -- denominator is every reservation that reached a real commitment (accepted or consumed); a still-held (never accepted) reservation is never a real promise and is excluded, the identical held-vs-accepted distinction batch 3''s own Tier C review already had to fix once for eligibility (ISS class, this checkpoint applies it from the first draft).';

create function app._calc_vendor_kpi_compliance(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  r app.vendor_kpi_calc_result;
begin
  select count(*) filter (where not e.eligibility_hold), count(*)
  into v_num, v_den
  from app.get_vendor_compliance_eligibility(p_vendor_master_id, p_actor_auth_user_id) e;

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case
    when not r.is_computable then 'no_tracked_requirements: no compliance requirement family is currently tracked for this vendor (app.get_vendor_compliance_eligibility, PRC-253)'
    else 'point_in_time: reflects the CURRENT compliance projection (app.vendor_compliance_status''s own last-computed snapshot), not a historical average over the window -- compliance eligibility is not itself a dated event series (Prompt 264 §22 "provisional partial-data view")'
  end;
  r.source_evidence := jsonb_build_object('tracked_families', coalesce(v_den, 0), 'not_on_hold', coalesce(v_num, 0));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_compliance is
  'PRC-264: reads app.get_vendor_compliance_eligibility (PRC-253) directly, never re-derives compliance status a second time (ADR-0020 single-canonical-source spirit). computed_value = % of currently-tracked requirement families NOT on eligibility_hold. Point-in-time by nature -- carries no window-scoped source_id set, so it is not disputable via app.vendor_kpi_source_disputes (a dispute belongs on the compliance document/waiver itself, PRC-253''s own scope).';

create function app._calc_vendor_kpi_claims_damage(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  with assigned as (
    select distinct ra.shipment_order_id
    from app.resource_assignments ra
    where ra.tenant_id = p_tenant_id and ra.role = 'vendor' and ra.resource_id = p_vendor_master_id
      and ra.effective_from >= p_window_start and ra.effective_from < p_window_end
  ),
  liable as (
    select distinct oe.shipment_order_id, cce.id as case_id
    from app.claim_case_extensions cce
    join app.operational_exceptions oe on oe.id = cce.operational_exception_id
    join app.claim_responsibility_reviews crr on crr.claim_case_id = cce.id and crr.is_current
    where crr.final_responsibility_party = 'vendor' and crr.status in ('approved', 'amended')
      and oe.shipment_order_id in (select shipment_order_id from assigned)
      and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'claims_damage' and d.source_id = cce.id and d.status = 'upheld')
  )
  select (select count(*) from assigned), (select count(*) from liable), (select array_agg(case_id) from liable)
  into v_den, v_num, v_ids;

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_assigned_shipments: no app.resource_assignments (role=vendor) row for this vendor has effective_from in the window' else null end;
  r.source_evidence := jsonb_build_object('assigned_shipments', coalesce(v_den, 0), 'vendor_liable_claims', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_claims_damage is
  'PRC-264: rate of shipments assigned to this vendor (app.resource_assignments, effective_from in window) that also have a DECIDED (approved/amended), vendor-liable claim case (app.claim_case_extensions/app.claim_responsibility_reviews.final_responsibility_party=vendor, ATW-025). A claim that resolves after the window still counts against the shipment''s own assignment window, never the claim''s own opened_at -- the assignment is the real unit being scored. Lower is better (target_operator=lte).';

create function app._calc_vendor_kpi_service_complaint_sla(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  with assigned as (
    select distinct ra.shipment_order_id
    from app.resource_assignments ra
    where ra.tenant_id = p_tenant_id and ra.role = 'vendor' and ra.resource_id = p_vendor_master_id
      and ra.effective_from >= p_window_start and ra.effective_from < p_window_end
  ),
  complaints as (
    select distinct oe.shipment_order_id, cce.id as case_id
    from app.claim_case_extensions cce
    join app.operational_exceptions oe on oe.id = cce.operational_exception_id
    where cce.claimant_type = 'customer'
      and oe.shipment_order_id in (select shipment_order_id from assigned)
      and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'service_complaint_sla' and d.source_id = cce.id and d.status = 'upheld')
  )
  select (select count(*) from assigned), (select count(*) from complaints), (select array_agg(case_id) from complaints)
  into v_den, v_num, v_ids;

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case
    when not r.is_computable then 'no_assigned_shipments: no app.resource_assignments (role=vendor) row for this vendor has effective_from in the window'
    else 'proxy_source: no dedicated customer-complaint/ticket domain exists anywhere in this repository -- this KPI is sourced from customer-claimant claim cases (app.claim_case_extensions.claimant_type=customer) against this vendor''s own assigned shipments, regardless of eventual liability finding (distinct from claims_damage, which requires a decided vendor-liable finding)'
  end;
  r.source_evidence := jsonb_build_object('assigned_shipments', coalesce(v_den, 0), 'customer_complaints', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_service_complaint_sla is
  'PRC-264: rate of shipments assigned to this vendor with a customer-initiated claim case (app.claim_case_extensions.claimant_type=customer), REGARDLESS of eventual liability -- a disclosed proxy for "customer complaint/SLA" since no dedicated ticket/complaint domain exists anywhere in this repository (Prompt 264 §15''s own named category, sourced honestly from the closest real evidence rather than fabricated). Lower is better (target_operator=lte).';

create function app._calc_vendor_kpi_rate_competitiveness(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_avg_score numeric;
  v_count integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  with vendor_rates as (
    select vr.id, vr.service_type, vr.origin_lane, vr.destination_lane, vr.currency, vr.base_amount
    from app.vendor_rate_versions vr
    where vr.tenant_id = p_tenant_id and vr.vendor_master_id = p_vendor_master_id and vr.approval_status = 'approved'
      and vr.effective_from < p_window_end and (vr.effective_to is null or vr.effective_to > p_window_start)
      and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'rate_competitiveness' and d.source_id = vr.id and d.status = 'upheld')
  ),
  scored as (
    select
      vrt.id,
      -- C-22 (docs/standards/RECURRING_DEFECT_TAXONOMY.md): the "market" a rate is ranked
      -- against is scoped to the SAME currency, not just the same lane/service -- base_amount
      -- is a bare numeric with no cross-currency normalization anywhere in this function, so
      -- comparing e.g. an IDR-denominated quote against a USD-denominated one for the same
      -- lane would rank almost purely by currency denomination, not real cost.
      (
        select count(*) from app.vendor_rate_versions m
        where m.tenant_id = p_tenant_id and m.service_type = vrt.service_type and m.origin_lane = vrt.origin_lane
          and coalesce(m.destination_lane, '') = coalesce(vrt.destination_lane, '') and m.currency = vrt.currency
          and m.approval_status = 'approved' and m.vendor_master_id is not null
          and m.effective_from < p_window_end and (m.effective_to is null or m.effective_to > p_window_start)
      ) as market_count,
      (
        select count(*) from app.vendor_rate_versions m
        where m.tenant_id = p_tenant_id and m.service_type = vrt.service_type and m.origin_lane = vrt.origin_lane
          and coalesce(m.destination_lane, '') = coalesce(vrt.destination_lane, '') and m.currency = vrt.currency
          and m.approval_status = 'approved' and m.vendor_master_id is not null
          and m.effective_from < p_window_end and (m.effective_to is null or m.effective_to > p_window_start)
          and m.base_amount <= vrt.base_amount
      ) as rank_le
    from vendor_rates vrt
  )
  select
    avg(case when market_count > 1 then 100.0 * (1 - (rank_le - 1)::numeric / (market_count - 1)) else 100.0 end),
    count(*),
    array_agg(id)
  into v_avg_score, v_count, v_ids
  from scored;

  r.raw_numerator := null;
  r.raw_denominator := v_count;
  r.sample_size := coalesce(v_count, 0);
  r.is_computable := coalesce(v_count, 0) > 0;
  r.computed_value := case when v_count > 0 then round(v_avg_score, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_vendor_rates: this vendor has no approved app.vendor_rate_versions row effective within the window' else 'market_percentile: 100 = cheapest among approved same-tenant vendor-linked rates for the same service_type/origin_lane/destination_lane/currency effective in the window, never a raw currency amount (design note 3) and never ranked against a different currency (taxonomy C-22)' end;
  r.source_evidence := jsonb_build_object('own_rate_versions', coalesce(v_count, 0), 'avg_percentile_score', r.computed_value, 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_rate_competitiveness is
  'PRC-264: for each of this vendor''s own approved app.vendor_rate_versions (COM-149/PRC-255, vendor_master_id-linked per ADR-0020) effective in the window, a market-percentile cost rank among every approved vendor-linked rate for the SAME (tenant, service_type, origin_lane, destination_lane, currency) -- 100 = this vendor is the cheapest, scaling down as more competitors undercut it. The currency leg of that scope key exists specifically so this ranking never compares two amounts denominated in different currencies (taxonomy C-22) -- no FX conversion is performed; a lane quoted by this vendor in a currency no competitor also quotes in simply has market_count=1 and scores 100 by definition, rather than being ranked against unrelated-currency numbers. Never reads app.vendor_comparison_offers/vendor_comparisons (PRC-258) -- rate versions alone are real, canonical, and already-scoped, avoiding a second, heavier evidence chain for the identical "cost competitiveness" signal (a disclosed, deliberate scope simplification, not an oversight).';

create function app._calc_vendor_kpi_rate_validity(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  v_num integer;
  v_den integer;
  v_ids uuid[];
  r app.vendor_kpi_calc_result;
begin
  select array_agg(id) into v_ids
  from app.vendor_rate_versions vr
  where vr.tenant_id = p_tenant_id and vr.vendor_master_id = p_vendor_master_id and vr.approval_status = 'approved'
    and vr.effective_from < p_window_end and (vr.effective_to is null or vr.effective_to > p_window_start)
    and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'rate_validity' and d.source_id = vr.id and d.status = 'upheld');

  with days as (
    select generate_series(p_window_start::date, (p_window_end - interval '1 day')::date, interval '1 day') as d
  )
  select
    count(*) filter (
      where exists (
        select 1 from app.vendor_rate_versions vr
        where vr.id = any (coalesce(v_ids, '{}'::uuid[]))
          and vr.effective_from <= days.d::timestamptz and (vr.effective_to is null or vr.effective_to > days.d::timestamptz)
      )
    ),
    count(*)
  into v_num, v_den
  from days;

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when v_num = 0 then 'no_valid_rate_coverage: this vendor has no approved rate version covering any day of the window' else null end;
  r.source_evidence := jsonb_build_object('window_days', coalesce(v_den, 0), 'covered_days', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_rate_validity is
  'PRC-264: % of calendar days in the window covered by at least one approved app.vendor_rate_versions row (effective_from/effective_to). is_computable is true whenever the window itself is non-empty (window_days is always > 0) -- a vendor with zero coverage genuinely scores 0%, a real, meaningful result, not a missing-data case (distinct from every other calculator, where a zero-denominator means "nothing to measure").';

create function app._calc_vendor_kpi_invoice_accuracy()
returns app.vendor_kpi_calc_result
language sql
immutable
as $$
  select null::numeric, null::numeric, 0, null::numeric, false,
    'not_yet_sourced: this KPI''s real evidence source is Prompt 265 (Vendor Invoice Matching / three-way-match variance against app.finance_vendor_bills, FIN-199/200), which has not been built as of this checkpoint (design note 2). app.vendor_kpi_definitions.is_computable=false for this kpi_code carries the same disclosure -- this function never queries anything and never fabricates a value.',
    '{}'::jsonb, 0;
$$;

comment on function app._calc_vendor_kpi_invoice_accuracy is
  'PRC-264 design note 2: the one calculator that computes nothing, by design and fully disclosed -- see the migration header and docs/runtime/KNOWN_ISSUES.md.';

-- ===========================================================================
-- 13. Dispatcher.
-- ===========================================================================

create function app._calculate_vendor_kpi_metric_value(
  p_tenant_id uuid, p_vendor_master_id uuid, p_kpi_code text,
  p_window_start timestamptz, p_window_end timestamptz, p_actor_auth_user_id uuid
)
returns app.vendor_kpi_calc_result
language plpgsql
stable
as $$
declare
  r app.vendor_kpi_calc_result;
begin
  case p_kpi_code
    when 'on_time_pickup' then r := app._calc_vendor_kpi_on_time_pickup(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'on_time_delivery' then r := app._calc_vendor_kpi_on_time_delivery(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'acceptance_rate' then r := app._calc_vendor_kpi_acceptance_rate(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'response_time' then r := app._calc_vendor_kpi_response_time(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'capacity_fulfillment' then r := app._calc_vendor_kpi_capacity_fulfillment(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'compliance' then r := app._calc_vendor_kpi_compliance(p_tenant_id, p_vendor_master_id, p_actor_auth_user_id);
    when 'claims_damage' then r := app._calc_vendor_kpi_claims_damage(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'service_complaint_sla' then r := app._calc_vendor_kpi_service_complaint_sla(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'rate_competitiveness' then r := app._calc_vendor_kpi_rate_competitiveness(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'rate_validity' then r := app._calc_vendor_kpi_rate_validity(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    when 'invoice_accuracy' then r := app._calc_vendor_kpi_invoice_accuracy();
    else
      raise exception 'invalid_kpi_code: % is not a supported KPI category', p_kpi_code using errcode = 'check_violation';
  end case;
  return r;
end;
$$;

comment on function app._calculate_vendor_kpi_metric_value is
  'PRC-264: the one dispatch point routing a kpi_code to its fixed built-in calculator (design note 1). Internal only -- no grant; app.calculate_vendor_kpi_metrics is the sole authorized caller.';

-- ===========================================================================
-- 14. KPI definition catalogue CRUD.
-- ===========================================================================

create function app.create_vendor_kpi_definition_draft(
  p_tenant_id uuid, p_kpi_code text, p_name text, p_description text,
  p_measurement_window_days integer, p_min_sample_size integer,
  p_target_value numeric, p_target_operator text, p_weight numeric, p_unit text,
  p_band_thresholds jsonb, p_exclusion_rules jsonb, p_rounding_scale integer,
  p_is_computable boolean, p_source_note text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.vendor_kpi_definitions;
  v_definition app.vendor_kpi_definitions;
  v_next_version integer;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_kpi_definitions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.kpi_code is distinct from p_kpi_code or v_existing.name is distinct from p_name
        or v_existing.measurement_window_days is distinct from p_measurement_window_days
        or v_existing.target_value is distinct from p_target_value or v_existing.target_operator is distinct from p_target_operator
        or v_existing.weight is distinct from p_weight
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different KPI definition draft', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  select coalesce(max(version_no), 0) + 1 into v_next_version from app.vendor_kpi_definitions where tenant_id = p_tenant_id and kpi_code = p_kpi_code;

  begin
    insert into app.vendor_kpi_definitions (
      tenant_id, kpi_code, version_no, name, description, measurement_window_days, min_sample_size,
      target_value, target_operator, weight, unit, band_thresholds, exclusion_rules, rounding_scale,
      is_computable, source_note, idempotency_key, created_by
    ) values (
      p_tenant_id, p_kpi_code, v_next_version, p_name, p_description, p_measurement_window_days, coalesce(p_min_sample_size, 1),
      p_target_value, p_target_operator, p_weight, p_unit, coalesce(p_band_thresholds, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb),
      coalesce(p_exclusion_rules, '{}'::jsonb), coalesce(p_rounding_scale, 2), coalesce(p_is_computable, true), p_source_note, p_idempotency_key, p_actor_label
    )
    returning * into v_definition;
  exception
    -- Race-recovery only -- a genuinely CONCURRENT idempotency-key insert lost the
    -- race after this function's own pre-check above already found nothing. Nested in
    -- its own block scoped to ONLY this INSERT (taxonomy C-02): the pre-check's own
    -- deliberate idempotency_key_conflict raise above uses the SAME errcode but lives
    -- OUTSIDE this block, so it is never accidentally caught and swallowed here.
    when unique_violation then
      select * into v_existing from app.vendor_kpi_definitions where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing.kpi_code is distinct from p_kpi_code or v_existing.name is distinct from p_name
        or v_existing.measurement_window_days is distinct from p_measurement_window_days
        or v_existing.target_value is distinct from p_target_value or v_existing.target_operator is distinct from p_target_operator
        or v_existing.weight is distinct from p_weight
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different KPI definition draft', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_vendor_kpi_definition_draft',
    'app.vendor_kpi_definitions', v_definition.id, 'success', null, null, jsonb_build_object('kpi_code', p_kpi_code)
  );

  return v_definition;
end;
$$;

comment on function app.create_vendor_kpi_definition_draft is
  'PRC-264: PRC:Edit. Idempotency replay compares the full target tuple (kpi_code/name/window/target/operator/weight) before returning the existing row -- a mismatch raises idempotency_key_conflict (taxonomy C-01). The race-recovery exception handler is nested to scope ONLY the INSERT statement, never the pre-check''s own deliberate raise (taxonomy C-02 -- found and fixed during this checkpoint''s own Tier B self-check, live-reproduced: a weight-mismatched replay was silently returning the stale row instead of raising, because the pre-check''s raise and a function-wide exception handler shared the same errcode).';

create function app.update_vendor_kpi_definition_draft(
  p_definition_id uuid, p_expected_version integer, p_name text, p_description text,
  p_measurement_window_days integer, p_min_sample_size integer,
  p_target_value numeric, p_target_operator text, p_weight numeric, p_unit text,
  p_band_thresholds jsonb, p_exclusion_rules jsonb, p_rounding_scale integer,
  p_is_computable boolean, p_source_note text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_definition app.vendor_kpi_definitions;
begin
  select * into v_definition from app.vendor_kpi_definitions where id = p_definition_id for update;
  if not found then
    raise exception 'vendor_kpi_definition_not_found: %', p_definition_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_definition.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_definition.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_definition.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI definition % expected version % but found %', p_definition_id, p_expected_version, v_definition.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_definition.status <> 'draft' then
    raise exception 'invalid_transition: vendor KPI definition % is % and cannot be edited', p_definition_id, v_definition.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_definitions
  set name = p_name, description = p_description, measurement_window_days = p_measurement_window_days,
      min_sample_size = coalesce(p_min_sample_size, 1), target_value = p_target_value, target_operator = p_target_operator,
      weight = p_weight, unit = p_unit, band_thresholds = coalesce(p_band_thresholds, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb),
      exclusion_rules = coalesce(p_exclusion_rules, '{}'::jsonb), rounding_scale = coalesce(p_rounding_scale, 2),
      is_computable = coalesce(p_is_computable, true), source_note = p_source_note
  where id = p_definition_id and record_version = p_expected_version
  returning * into v_definition;
  if not found then
    raise exception 'stale_version: vendor KPI definition % target row was concurrently modified (expected version %)', p_definition_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_definition.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_kpi_definition_draft',
    'app.vendor_kpi_definitions', v_definition.id, 'success', null, null, '{}'::jsonb
  );

  return v_definition;
end;
$$;

comment on function app.update_vendor_kpi_definition_draft is 'PRC-264: PRC:Edit, draft status only. Every editable field is direct-assigned (never coalesce-preserve) -- every column here is NOT NULL on the base table, so a caller omitting a real value fails fast on the NOT NULL constraint rather than silently clearing anything (distinct from vendor_contracts'' own nullable commercial-term fields, where coalesce-preserve is the correct shape).';

create function app.publish_vendor_kpi_definition(p_definition_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_definition app.vendor_kpi_definitions;
  v_superseded app.vendor_kpi_definitions;
begin
  select * into v_definition from app.vendor_kpi_definitions where id = p_definition_id for update;
  if not found then
    raise exception 'vendor_kpi_definition_not_found: %', p_definition_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_definition.tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_definition.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_definition.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI definition % expected version % but found %', p_definition_id, p_expected_version, v_definition.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_definition.status <> 'draft' then
    raise exception 'invalid_transition: vendor KPI definition % is % and cannot be published', p_definition_id, v_definition.status
      using errcode = 'check_violation';
  end if;

  select * into v_superseded from app.vendor_kpi_definitions
  where tenant_id = v_definition.tenant_id and kpi_code = v_definition.kpi_code and status = 'published' and id <> v_definition.id
  for update;
  if found then
    update app.vendor_kpi_definitions set status = 'archived', updated_at = now(), record_version = record_version + 1
    where id = v_superseded.id and record_version = v_superseded.record_version and status = 'published';
    if not found then
      raise exception 'stale_version: superseded vendor KPI definition % was concurrently modified', v_superseded.id using errcode = 'serialization_failure';
    end if;
  end if;

  update app.vendor_kpi_definitions
  set status = 'published', supersedes_definition_id = v_superseded.id, updated_at = now(), record_version = record_version + 1
  where id = p_definition_id and record_version = p_expected_version
  returning * into v_definition;
  if not found then
    raise exception 'stale_version: vendor KPI definition % target row was concurrently modified (expected version %)', p_definition_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_definition.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_kpi_definition',
    'app.vendor_kpi_definitions', v_definition.id, 'success', null, null, jsonb_build_object('supersedes_definition_id', v_superseded.id)
  );

  return v_definition;
end;
$$;

comment on function app.publish_vendor_kpi_definition is
  'PRC-264: PRC:Approve. Auto-detects and archives (record_version-guarded, locked FIRST -- design mirrors app.publish_vendor_compliance_requirement''s own established lock order) any existing published row for the SAME (tenant_id, kpi_code) before publishing this one -- a tenant never needs to pass a separate supersedes id, since kpi_code (unlike a free-text contract_number) already uniquely identifies the logical KPI.';

create function app.archive_vendor_kpi_definition(p_definition_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_definition app.vendor_kpi_definitions;
begin
  select * into v_definition from app.vendor_kpi_definitions where id = p_definition_id for update;
  if not found then
    raise exception 'vendor_kpi_definition_not_found: %', p_definition_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_definition.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_definition.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_definition.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI definition % expected version % but found %', p_definition_id, p_expected_version, v_definition.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_definition.status not in ('draft', 'published') then
    raise exception 'invalid_transition: vendor KPI definition % is % and cannot be archived', p_definition_id, v_definition.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_definitions set status = 'archived', updated_at = now(), record_version = record_version + 1
  where id = p_definition_id and record_version = p_expected_version
  returning * into v_definition;
  if not found then
    raise exception 'stale_version: vendor KPI definition % target row was concurrently modified (expected version %)', p_definition_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_definition.tenant_id, p_actor_auth_user_id, p_actor_label, 'archive_vendor_kpi_definition',
    'app.vendor_kpi_definitions', v_definition.id, 'success', p_reason, null, '{}'::jsonb
  );

  return v_definition;
end;
$$;

create function app.get_vendor_kpi_definition(p_definition_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_definition app.vendor_kpi_definitions;
begin
  select * into v_definition from app.vendor_kpi_definitions where id = p_definition_id;
  if not found or not app.has_active_tenant_membership(v_definition.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_definition_not_found: %', p_definition_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_definition.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_definition.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_definition;
end;
$$;

comment on function app.get_vendor_kpi_definition is 'PRC-264: not-found and cross-tenant/no-membership are folded into the SAME vendor_kpi_definition_not_found error, checked BEFORE the permission evaluation, so no real row content is ever disclosed to a caller outside the owning tenant (taxonomy C-05, applied from the first draft).';

create function app.list_vendor_kpi_definitions(p_tenant_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.vendor_kpi_definitions
  where tenant_id = p_tenant_id and (p_status is null or status = p_status)
  order by kpi_code, version_no desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

create function app.list_vendor_kpi_definition_versions(p_tenant_id uuid, p_kpi_code text, p_actor_auth_user_id uuid)
returns setof app.vendor_kpi_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.vendor_kpi_definitions
  where tenant_id = p_tenant_id and kpi_code = p_kpi_code
  order by version_no desc;
end;
$$;

-- ===========================================================================
-- 15. Source disputes -- design note 4.
-- ===========================================================================

create function app.raise_vendor_kpi_source_dispute(
  p_tenant_id uuid, p_vendor_master_id uuid, p_kpi_code text, p_source_id uuid, p_source_label text, p_reason text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_kpi_source_disputes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_dispute app.vendor_kpi_source_disputes;
begin
  -- C-05 (docs/standards/RECURRING_DEFECT_TAXONOMY.md): evaluate_permission runs before any
  -- row lookup that could disclose whether p_vendor_master_id exists in this tenant to a
  -- caller not yet confirmed to hold any PRC permission here (matches
  -- create_vendor_contract_draft's own precedent order).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to raise a vendor KPI source dispute' using errcode = 'check_violation';
  end if;

  insert into app.vendor_kpi_source_disputes (tenant_id, vendor_master_id, kpi_code, source_id, source_label, reason, raised_by_auth_user_id, raised_by, created_by)
  values (p_tenant_id, p_vendor_master_id, p_kpi_code, p_source_id, p_source_label, p_reason, p_actor_auth_user_id, p_actor_label, p_actor_label)
  returning * into v_dispute;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'raise_vendor_kpi_source_dispute',
    'app.vendor_kpi_source_disputes', v_dispute.id, 'success', p_reason, null, jsonb_build_object('kpi_code', p_kpi_code, 'source_id', p_source_id)
  );

  return v_dispute;
exception
  when unique_violation then
    raise exception 'dispute_already_pending: source % already has a pending dispute for kpi_code % against this vendor', p_source_id, p_kpi_code using errcode = 'unique_violation';
end;
$$;

comment on function app.raise_vendor_kpi_source_dispute is 'PRC-264: PRC:Edit, staff-recorded on the vendor''s own behalf (no vendor-portal identity exists, design note 4). At most one pending dispute per (kpi_code, source_id, vendor_master_id) -- a genuine unique_violation race is translated into the same typed dispute_already_pending error the pre-check would have raised, never a raw constraint-name leak.';

create function app.decide_vendor_kpi_source_dispute(p_dispute_id uuid, p_expected_version integer, p_decision text, p_decision_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_source_disputes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_dispute app.vendor_kpi_source_disputes;
begin
  select * into v_dispute from app.vendor_kpi_source_disputes where id = p_dispute_id for update;
  if not found then
    raise exception 'vendor_kpi_dispute_not_found: %', p_dispute_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_dispute.tenant_id, 'PRC', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_dispute.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_dispute.raised_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % raised dispute % and may not also decide it', p_actor_auth_user_id, p_dispute_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_dispute.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI source dispute % expected version % but found %', p_dispute_id, p_expected_version, v_dispute.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_dispute.status <> 'pending' then
    raise exception 'invalid_transition: vendor KPI source dispute % is % and cannot be decided', p_dispute_id, v_dispute.status
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('upheld', 'rejected') then
    raise exception 'invalid_decision: % is not one of upheld/rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'reason_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_source_disputes
  set status = p_decision, decided_by_auth_user_id = p_actor_auth_user_id, decided_by = p_actor_label, decided_at = now(), decision_notes = p_decision_notes
  where id = p_dispute_id and record_version = p_expected_version
  returning * into v_dispute;
  if not found then
    raise exception 'stale_version: vendor KPI source dispute % target row was concurrently modified (expected version %)', p_dispute_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_dispute.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_kpi_source_dispute',
    'app.vendor_kpi_source_disputes', v_dispute.id, 'success', p_decision_notes, null, jsonb_build_object('status', v_dispute.status)
  );

  return v_dispute;
end;
$$;

comment on function app.decide_vendor_kpi_source_dispute is 'PRC-264: PRC:Approve, self-decide blocked (raised_by <> decided_by, mirrors app.decide_claim_responsibility). An upheld dispute excludes its own source_id from every FUTURE app.calculate_vendor_kpi_metrics run for the same kpi_code -- never retroactively rewrites an already-published scorecard (Prompt 264 §24: "never silent historical rewrite").';

create function app.get_vendor_kpi_source_dispute(p_dispute_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_kpi_source_disputes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_dispute app.vendor_kpi_source_disputes;
begin
  select * into v_dispute from app.vendor_kpi_source_disputes where id = p_dispute_id;
  if not found or not app.has_active_tenant_membership(v_dispute.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_dispute_not_found: %', p_dispute_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_dispute.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_dispute.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_dispute;
end;
$$;

create function app.list_vendor_kpi_source_disputes(p_tenant_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid)
returns setof app.vendor_kpi_source_disputes
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.vendor_kpi_source_disputes
  where tenant_id = p_tenant_id and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id) and (p_status is null or status = p_status)
  order by raised_at desc;
end;
$$;

-- ===========================================================================
-- 16. Measurement (calculate/recalculate) and scorecard publish.
-- ===========================================================================

create function app.calculate_vendor_kpi_metrics(
  p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz,
  p_triggered_by text, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns setof app.vendor_kpi_metric_values
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_existing_run app.vendor_kpi_measurement_runs;
  v_run app.vendor_kpi_measurement_runs;
  v_definition app.vendor_kpi_definitions;
  v_result app.vendor_kpi_calc_result;
  v_current app.vendor_kpi_metric_values;
  v_current_found boolean;
  v_new app.vendor_kpi_metric_values;
  v_normalized numeric;
  v_excluded_count integer;
  v_kpi_count integer := 0;
  v_computable_count integer := 0;
  v_checkpoint jsonb := '{}'::jsonb;
begin
  -- C-05: permission check before the vendor existence lookup (see raise_vendor_kpi_source_dispute's own comment above for the precedent this follows).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
  end if;

  if p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;
  if p_triggered_by not in ('scheduled', 'manual', 'recalculation') then
    raise exception 'invalid_triggered_by: % is not one of scheduled/manual/recalculation', p_triggered_by using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing_run from app.vendor_kpi_measurement_runs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing_run.vendor_master_id is distinct from p_vendor_master_id
        or v_existing_run.window_start is distinct from p_window_start or v_existing_run.window_end is distinct from p_window_end
        or v_existing_run.triggered_by is distinct from p_triggered_by
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different vendor KPI measurement run', p_idempotency_key using errcode = 'unique_violation';
      end if;
      -- RETURN QUERY does not itself exit a set-returning function -- the explicit
      -- bare RETURN below is required or execution would fall through into the INSERT
      -- and definition loop below, producing duplicate rows and a spurious second run.
      return query select * from app.vendor_kpi_metric_values where run_id = v_existing_run.id order by kpi_code;
      return;
    end if;
  end if;

  begin
    insert into app.vendor_kpi_measurement_runs (tenant_id, vendor_master_id, window_start, window_end, triggered_by, idempotency_key, created_by)
    values (p_tenant_id, p_vendor_master_id, p_window_start, p_window_end, p_triggered_by, p_idempotency_key, p_actor_label)
    returning * into v_run;
  exception
    -- Race-recovery only, nested to scope ONLY this INSERT (taxonomy C-02) -- a
    -- genuinely concurrent identical-key submission that lost the race returns the
    -- winner's own run/metrics instead of a raw unique_violation.
    when unique_violation then
      select * into v_existing_run from app.vendor_kpi_measurement_runs where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_existing_run.vendor_master_id is distinct from p_vendor_master_id
        or v_existing_run.window_start is distinct from p_window_start or v_existing_run.window_end is distinct from p_window_end
        or v_existing_run.triggered_by is distinct from p_triggered_by
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different vendor KPI measurement run', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return query select * from app.vendor_kpi_metric_values where run_id = v_existing_run.id order by kpi_code;
      return;
  end;

  for v_definition in
    select * from app.vendor_kpi_definitions where tenant_id = p_tenant_id and status = 'published' order by kpi_code
  loop
    v_kpi_count := v_kpi_count + 1;

    -- Lock the prior current row (if any) FIRST, before deciding whether to supersede it
    -- (taxonomy C-04) -- a concurrent recalculation for the SAME (vendor, kpi_code,
    -- window) serializes through this one lock.
    select * into v_current from app.vendor_kpi_metric_values
    where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id and kpi_code = v_definition.kpi_code
      and window_start = p_window_start and window_end = p_window_end and is_current
    for update;
    -- FOUND must be captured IMMEDIATELY -- every subsequent statement in this loop
    -- (including the app._calculate_vendor_kpi_metric_value call below) executes its
    -- own SQL and overwrites the ambient FOUND, so reading the bare FOUND keyword
    -- later in this iteration would silently reflect that LATER statement's own
    -- result, not this SELECT's. Real bug, live-caught by this checkpoint's own db-test
    -- (a disputed-event recalculation was silently taking the "unchanged" short-circuit
    -- because FOUND had already been overwritten to false by the dispatcher call).
    v_current_found := found;

    if not v_definition.is_computable then
      v_result.raw_numerator := null;
      v_result.raw_denominator := null;
      v_result.sample_size := 0;
      v_result.is_computable := false;
      v_result.computed_value := null;
      v_result.computation_note := coalesce(v_definition.source_note, 'not_computable: this KPI definition is marked is_computable=false');
      v_result.source_evidence := '{}'::jsonb;
    else
      v_result := app._calculate_vendor_kpi_metric_value(p_tenant_id, p_vendor_master_id, v_definition.kpi_code, p_window_start, p_window_end, p_actor_auth_user_id);
      if v_result.is_computable and v_result.sample_size < v_definition.min_sample_size then
        v_result.is_computable := false;
        v_result.computation_note := format('insufficient_sample: sample_size %s is below this definition''s own required minimum %s', v_result.sample_size, v_definition.min_sample_size);
      end if;
    end if;

    v_normalized := case when v_result.is_computable then app._normalize_vendor_kpi_score(v_result.computed_value, v_definition.target_value, v_definition.target_operator) else null end;
    if v_result.is_computable then
      v_computable_count := v_computable_count + 1;
    end if;

    -- Count of currently-upheld source disputes on file for this (vendor, kpi_code) --
    -- computed once here, generically, rather than duplicated inside all nine
    -- calculators (each of which already excludes upheld-disputed source_ids from its
    -- own numerator/denominator via its own NOT EXISTS filter; this is the audit-facing
    -- tally of how many, §18).
    select count(*) into v_excluded_count from app.vendor_kpi_source_disputes
    where kpi_code = v_definition.kpi_code and vendor_master_id = p_vendor_master_id and status = 'upheld';

    v_checkpoint := v_checkpoint || jsonb_build_object(v_definition.kpi_code, jsonb_build_object('sample_size', v_result.sample_size, 'is_computable', v_result.is_computable, 'checked_at', now()));

    -- Unchanged from the current row (same computed_value/sample_size/is_computable) --
    -- no new version, the real result IS the existing row (Prompt 264 §24 "never silent
    -- historical rewrite" cuts both ways: no genuine change means no churn either).
    if v_current_found and v_current.is_computable = v_result.is_computable
      and v_current.computed_value is not distinct from v_result.computed_value
      and v_current.sample_size = v_result.sample_size
      and v_current.excluded_count = v_excluded_count
    then
      return next v_current;
      continue;
    end if;

    if v_current_found then
      update app.vendor_kpi_metric_values set is_current = false where id = v_current.id;
    end if;

    insert into app.vendor_kpi_metric_values (
      tenant_id, vendor_master_id, kpi_definition_id, kpi_code, window_start, window_end, version_no, run_id,
      raw_numerator, raw_denominator, sample_size, computed_value, normalized_score, is_computable, computation_note,
      source_evidence, excluded_count, supersedes_metric_value_id, created_by
    ) values (
      p_tenant_id, p_vendor_master_id, v_definition.id, v_definition.kpi_code, p_window_start, p_window_end,
      coalesce(v_current.version_no, 0) + 1, v_run.id,
      v_result.raw_numerator, v_result.raw_denominator, coalesce(v_result.sample_size, 0), v_result.computed_value, v_normalized,
      v_result.is_computable, v_result.computation_note, coalesce(v_result.source_evidence, '{}'::jsonb), v_excluded_count, v_current.id, p_actor_label
    )
    returning * into v_new;

    return next v_new;
  end loop;

  update app.vendor_kpi_measurement_runs set kpi_count = v_kpi_count, computable_count = v_computable_count, source_checkpoint = v_checkpoint where id = v_run.id;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'calculate_vendor_kpi_metrics',
    'app.vendor_kpi_measurement_runs', v_run.id, 'success', null, null,
    jsonb_build_object('vendor_master_id', p_vendor_master_id, 'kpi_count', v_kpi_count, 'computable_count', v_computable_count)
  );

  return;
end;
$$;

comment on function app.calculate_vendor_kpi_metrics is
  'PRC-264: PRC:Edit. Loops every PUBLISHED definition for the tenant, dispatches each to app._calculate_vendor_kpi_metric_value, applies the definition''s own min_sample_size gate, and versions app.vendor_kpi_metric_values only on a genuine change -- the current row for each (vendor, kpi_code, window) is locked FIRST (taxonomy C-04) before the supersede decision. Idempotency replay compares the full target tuple (vendor/window/triggered_by, taxonomy C-01).';

create function app.publish_vendor_kpi_scorecard(
  p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_kpi_scorecards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_existing app.vendor_kpi_scorecards;
  v_current app.vendor_kpi_scorecards;
  v_scorecard app.vendor_kpi_scorecards;
  v_metric app.vendor_kpi_metric_values;
  v_definition app.vendor_kpi_definitions;
  v_line_count integer := 0;
  v_weighted_sum numeric := 0;
  v_computable_weight numeric := 0;
  v_total_weight numeric := 0;
  v_composite numeric;
  v_band text;
  v_run_id uuid;
  v_default_bands constant jsonb := '{"excellent": 90, "good": 75, "watch": 60}'::jsonb;
begin
  -- C-05: permission check before the vendor existence lookup (see raise_vendor_kpi_source_dispute's own comment above for the precedent this follows).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Approve');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
  end if;

  if p_window_end <= p_window_start then
    raise exception 'invalid_window: window_end must be after window_start' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_kpi_scorecards where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_id is distinct from p_vendor_master_id
        or v_existing.window_start is distinct from p_window_start or v_existing.window_end is distinct from p_window_end
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different vendor KPI scorecard', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  -- Lock the prior current scorecard FIRST (taxonomy C-04), before deciding to supersede it.
  select * into v_current from app.vendor_kpi_scorecards
  where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id and window_start = p_window_start and window_end = p_window_end and is_current
  for update;

  for v_metric in
    select * from app.vendor_kpi_metric_values
    where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id and window_start = p_window_start and window_end = p_window_end and is_current
    order by kpi_code
  loop
    select * into v_definition from app.vendor_kpi_definitions where id = v_metric.kpi_definition_id;
    v_line_count := v_line_count + 1;
    v_total_weight := v_total_weight + v_definition.weight;
    if v_metric.is_computable then
      v_computable_weight := v_computable_weight + v_definition.weight;
      v_weighted_sum := v_weighted_sum + (v_definition.weight * v_metric.normalized_score);
    end if;
    if v_run_id is null then
      v_run_id := v_metric.run_id;
    end if;
  end loop;

  if v_line_count = 0 then
    raise exception 'metrics_not_calculated: no vendor KPI metric values exist for this vendor/window -- call app.calculate_vendor_kpi_metrics first' using errcode = 'check_violation';
  end if;
  if v_computable_weight = 0 then
    raise exception 'insufficient_kpi_coverage: none of the % KPI categories considered for this vendor/window are computable', v_line_count using errcode = 'check_violation';
  end if;

  v_composite := round(v_weighted_sum / v_computable_weight, 2);
  v_band := app._band_for_score(v_composite, v_default_bands);

  if v_current.id is not null then
    update app.vendor_kpi_scorecards set is_current = false, status = 'superseded', updated_at = now(), record_version = record_version + 1
    where id = v_current.id and record_version = v_current.record_version;
    if not found then
      raise exception 'stale_version: vendor KPI scorecard % was concurrently modified', v_current.id using errcode = 'serialization_failure';
    end if;
  end if;

  begin
    insert into app.vendor_kpi_scorecards (
      tenant_id, vendor_master_id, window_start, window_end, version_no, composite_score, band,
      computable_weight_total, total_weight_defined, coverage_note, run_id, supersedes_scorecard_id,
      published_by_auth_user_id, published_by, idempotency_key, created_by
    ) values (
      p_tenant_id, p_vendor_master_id, p_window_start, p_window_end, coalesce(v_current.version_no, 0) + 1, v_composite, v_band,
      v_computable_weight, v_total_weight,
      format('%s of %s KPI categories computable (weight %s of %s)', (
        select count(*) from app.vendor_kpi_metric_values where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id and window_start = p_window_start and window_end = p_window_end and is_current and is_computable
      ), v_line_count, v_computable_weight, v_total_weight),
      v_run_id, v_current.id, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_scorecard;
  exception
    -- Race-recovery only, nested to scope ONLY this INSERT (taxonomy C-02) -- the
    -- winner of a genuine concurrent identical-key publish already inserted both the
    -- scorecard AND its lines; the loser returns that same row rather than attempting
    -- a second, now-conflicting lines insert.
    when unique_violation then
      select * into v_scorecard from app.vendor_kpi_scorecards where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_scorecard.vendor_master_id is distinct from p_vendor_master_id
        or v_scorecard.window_start is distinct from p_window_start or v_scorecard.window_end is distinct from p_window_end
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different vendor KPI scorecard', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_scorecard;
  end;

  for v_metric in
    select * from app.vendor_kpi_metric_values
    where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id and window_start = p_window_start and window_end = p_window_end and is_current
    order by kpi_code
  loop
    select * into v_definition from app.vendor_kpi_definitions where id = v_metric.kpi_definition_id;
    insert into app.vendor_kpi_scorecard_lines (
      tenant_id, scorecard_id, metric_value_id, kpi_definition_id, kpi_code, kpi_name_snapshot, weight_snapshot,
      target_value_snapshot, target_operator_snapshot, band_thresholds_snapshot, computed_value, normalized_score, band, is_computable
    ) values (
      p_tenant_id, v_scorecard.id, v_metric.id, v_definition.id, v_definition.kpi_code, v_definition.name, v_definition.weight,
      v_definition.target_value, v_definition.target_operator, v_definition.band_thresholds, v_metric.computed_value, v_metric.normalized_score,
      case when v_metric.is_computable then app._band_for_score(v_metric.normalized_score, v_definition.band_thresholds) else null end,
      v_metric.is_computable
    );
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_vendor_kpi_scorecard',
    'app.vendor_kpi_scorecards', v_scorecard.id, 'success', null,
    case when v_current.id is not null then jsonb_build_object('composite_score', v_current.composite_score, 'band', v_current.band) else null end,
    jsonb_build_object('composite_score', v_composite, 'band', v_band, 'computable_weight_total', v_computable_weight, 'total_weight_defined', v_total_weight)
  );

  return v_scorecard;
end;
$$;

comment on function app.publish_vendor_kpi_scorecard is
  'PRC-264: PRC:Approve ("Procurement managers review", §26). Requires app.calculate_vendor_kpi_metrics to have already run for the exact window (metrics_not_calculated otherwise). composite_score renormalizes weight over is_computable lines ONLY (design note 7) -- insufficient_kpi_coverage blocks publish only when NOTHING is computable, never a partial-coverage publish. Every published definition, computable or not, gets its own scorecard line (design note in app.vendor_kpi_scorecard_lines'' own comment) -- "all required categories covered or explicitly not applicable" is this loop''s own structural guarantee.';

-- ===========================================================================
-- 17. Scorecard/run read RPCs.
-- ===========================================================================

create function app.get_vendor_kpi_scorecard(p_scorecard_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_kpi_scorecards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_scorecard app.vendor_kpi_scorecards;
begin
  select * into v_scorecard from app.vendor_kpi_scorecards where id = p_scorecard_id;
  if not found or not app.has_active_tenant_membership(v_scorecard.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_scorecard_not_found: %', p_scorecard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_scorecard.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_scorecard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_scorecard;
end;
$$;

comment on function app.get_vendor_kpi_scorecard is 'PRC-264: not-found and cross-tenant/no-membership fold into the SAME vendor_kpi_scorecard_not_found error, checked before PRC:View (taxonomy C-05).';

create function app.get_vendor_kpi_scorecard_drilldown(p_scorecard_id uuid, p_actor_auth_user_id uuid)
returns table (
  line_id uuid, kpi_code text, kpi_name_snapshot text, weight_snapshot numeric, target_value_snapshot numeric,
  target_operator_snapshot text, band_thresholds_snapshot jsonb, computed_value numeric, normalized_score numeric,
  band text, is_computable boolean, adjusted boolean,
  raw_numerator numeric, raw_denominator numeric, sample_size integer, excluded_count integer,
  computation_note text, source_evidence jsonb, calculated_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_scorecard app.vendor_kpi_scorecards;
  v_masked boolean;
begin
  select * into v_scorecard from app.vendor_kpi_scorecards where id = p_scorecard_id;
  if not found or not app.has_active_tenant_membership(v_scorecard.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_scorecard_not_found: %', p_scorecard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_scorecard.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_scorecard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_masked := not app.has_prc_view_cost(v_scorecard.tenant_id, p_actor_auth_user_id);

  return query
  select l.id, l.kpi_code, l.kpi_name_snapshot, l.weight_snapshot, l.target_value_snapshot, l.target_operator_snapshot,
    l.band_thresholds_snapshot, l.computed_value, l.normalized_score, l.band, l.is_computable, l.adjusted,
    m.raw_numerator, m.raw_denominator, m.sample_size, m.excluded_count, m.computation_note,
    app.mask_vendor_kpi_source_evidence(m.source_evidence, v_masked), m.calculated_at
  from app.vendor_kpi_scorecard_lines l
  left join app.vendor_kpi_metric_values m on m.id = l.metric_value_id
  where l.scorecard_id = p_scorecard_id
  order by l.kpi_code;
end;
$$;

comment on function app.get_vendor_kpi_scorecard_drilldown is
  'PRC-264: the source-drilldown surface (Prompt 264 §15). contributing_source_ids is stripped from source_evidence for any caller without PRC:View cost (design note 3) -- every other key (counts/rates/notes) stays visible to any PRC:View holder.';

create function app.list_vendor_kpi_scorecards(p_tenant_id uuid, p_vendor_master_id uuid, p_actor_auth_user_id uuid, p_limit integer default 25)
returns setof app.vendor_kpi_scorecards
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_vendor_master_id is null then
    return query
    select * from app.vendor_kpi_scorecards
    where tenant_id = p_tenant_id and is_current
    order by window_end desc
    limit least(coalesce(p_limit, 25), 200);
  else
    return query
    select * from app.vendor_kpi_scorecards
    where tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id
    order by window_start desc, version_no desc
    limit least(coalesce(p_limit, 25), 200);
  end if;
end;
$$;

comment on function app.list_vendor_kpi_scorecards is
  'PRC-264: p_vendor_master_id=null lists the latest CURRENT scorecard per vendor across the tenant (the queue view); a supplied vendor id lists that one vendor''s full version history instead, current and superseded (the version-diff surface).';

create function app.get_vendor_kpi_measurement_run(p_run_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_kpi_measurement_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_run app.vendor_kpi_measurement_runs;
begin
  select * into v_run from app.vendor_kpi_measurement_runs where id = p_run_id;
  if not found or not app.has_active_tenant_membership(v_run.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_measurement_run_not_found: %', p_run_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_run.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_run.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_run;
end;
$$;

-- ===========================================================================
-- 18. Issues and corrective actions.
-- ===========================================================================

create function app.raise_vendor_performance_issue(
  p_tenant_id uuid, p_vendor_master_id uuid, p_scorecard_id uuid, p_kpi_code text, p_severity text, p_title text, p_description text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_performance_issues
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_existing app.vendor_performance_issues;
  v_issue app.vendor_performance_issues;
begin
  -- C-05: permission check before the vendor existence lookup (see raise_vendor_kpi_source_dispute's own comment above for the precedent this follows).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
  end if;

  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'title_required: a non-empty title is required to raise a vendor performance issue' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_performance_issues where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_id is distinct from p_vendor_master_id or v_existing.title is distinct from p_title or v_existing.severity is distinct from p_severity then
        raise exception 'idempotency_key_conflict: key % was already used for a different vendor performance issue', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  if p_scorecard_id is not null and not exists (select 1 from app.vendor_kpi_scorecards where id = p_scorecard_id and tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id) then
    raise exception 'vendor_kpi_scorecard_not_found: % does not belong to vendor % in tenant %', p_scorecard_id, p_vendor_master_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  begin
    insert into app.vendor_performance_issues (
      tenant_id, vendor_master_id, scorecard_id, kpi_code, severity, title, description, raised_by_auth_user_id, raised_by, idempotency_key, created_by
    ) values (
      p_tenant_id, p_vendor_master_id, p_scorecard_id, p_kpi_code, p_severity, p_title, p_description, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_issue;
  exception
    -- Race-recovery only, nested to scope ONLY this INSERT (taxonomy C-02).
    when unique_violation then
      select * into v_issue from app.vendor_performance_issues where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_issue.vendor_master_id is distinct from p_vendor_master_id or v_issue.title is distinct from p_title or v_issue.severity is distinct from p_severity then
        raise exception 'idempotency_key_conflict: key % was already used for a different vendor performance issue', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_issue;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'raise_vendor_performance_issue',
    'app.vendor_performance_issues', v_issue.id, 'success', null, null, jsonb_build_object('severity', p_severity, 'kpi_code', p_kpi_code)
  );

  return v_issue;
end;
$$;

create function app.update_vendor_performance_issue_status(p_issue_id uuid, p_expected_version integer, p_status text, p_resolution_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_performance_issues
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_issue app.vendor_performance_issues;
begin
  select * into v_issue from app.vendor_performance_issues where id = p_issue_id for update;
  if not found then
    raise exception 'vendor_performance_issue_not_found: %', p_issue_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_issue.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_issue.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_issue.record_version <> p_expected_version then
    raise exception 'stale_version: vendor performance issue % expected version % but found %', p_issue_id, p_expected_version, v_issue.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_status not in ('open', 'in_progress', 'resolved', 'closed') then
    raise exception 'invalid_status: % is not one of open/in_progress/resolved/closed', p_status using errcode = 'check_violation';
  end if;
  if v_issue.status in ('resolved', 'closed') and p_status not in ('resolved', 'closed') then
    raise exception 'invalid_transition: vendor performance issue % is already % and cannot be reopened via this path', p_issue_id, v_issue.status
      using errcode = 'check_violation';
  end if;

  update app.vendor_performance_issues
  set status = p_status, resolution_note = coalesce(p_resolution_note, resolution_note),
    resolved_by_auth_user_id = case when p_status in ('resolved', 'closed') then p_actor_auth_user_id else resolved_by_auth_user_id end,
    resolved_by = case when p_status in ('resolved', 'closed') then p_actor_label else resolved_by end,
    resolved_at = case when p_status in ('resolved', 'closed') then coalesce(v_issue.resolved_at, now()) else resolved_at end
  where id = p_issue_id and record_version = p_expected_version
  returning * into v_issue;
  if not found then
    raise exception 'stale_version: vendor performance issue % target row was concurrently modified (expected version %)', p_issue_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_issue.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_performance_issue_status',
    'app.vendor_performance_issues', v_issue.id, 'success', p_resolution_note, null, jsonb_build_object('status', v_issue.status)
  );

  return v_issue;
end;
$$;

create function app.get_vendor_performance_issue(p_issue_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_performance_issues
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_issue app.vendor_performance_issues;
begin
  select * into v_issue from app.vendor_performance_issues where id = p_issue_id;
  if not found or not app.has_active_tenant_membership(v_issue.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_performance_issue_not_found: %', p_issue_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_issue.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_issue.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_issue;
end;
$$;

create function app.list_vendor_performance_issues(p_tenant_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.vendor_performance_issues
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.vendor_performance_issues
  where tenant_id = p_tenant_id and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id) and (p_status is null or status = p_status)
  order by raised_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

-- Internal only (no grant) -- a corrective action landing on a still-open issue
-- advances it to in_progress; never touches an issue already resolved/closed/
-- in_progress (idempotent, silent no-op otherwise).
create function app.advance_vendor_performance_issue_in_progress(p_issue_id uuid)
returns void
language sql
security definer
set search_path = app, pg_temp
as $$
  update app.vendor_performance_issues set status = 'in_progress' where id = p_issue_id and status = 'open';
$$;

create function app.add_vendor_performance_corrective_action(
  p_issue_id uuid, p_description text, p_owner_label text, p_due_date date, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_performance_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_issue app.vendor_performance_issues;
  v_existing app.vendor_performance_corrective_actions;
  v_action app.vendor_performance_corrective_actions;
begin
  select * into v_issue from app.vendor_performance_issues where id = p_issue_id;
  if not found then
    raise exception 'vendor_performance_issue_not_found: %', p_issue_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_issue.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_issue.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'description_required: a non-empty description is required for a corrective action' using errcode = 'check_violation';
  end if;
  if v_issue.status = 'closed' then
    raise exception 'invalid_transition: vendor performance issue % is closed and cannot accept a new corrective action', p_issue_id using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_performance_corrective_actions where tenant_id = v_issue.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.issue_id is distinct from p_issue_id or v_existing.description is distinct from p_description then
        raise exception 'idempotency_key_conflict: key % was already used for a different corrective action', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_performance_corrective_actions (tenant_id, issue_id, description, owner_label, due_date, idempotency_key, created_by)
    values (v_issue.tenant_id, p_issue_id, p_description, p_owner_label, p_due_date, p_idempotency_key, p_actor_label)
    returning * into v_action;
  exception
    -- Race-recovery only, nested to scope ONLY this INSERT (taxonomy C-02).
    when unique_violation then
      select * into v_action from app.vendor_performance_corrective_actions where tenant_id = v_issue.tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_action.issue_id is distinct from p_issue_id or v_action.description is distinct from p_description then
        raise exception 'idempotency_key_conflict: key % was already used for a different corrective action', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_action;
  end;

  perform app.advance_vendor_performance_issue_in_progress(p_issue_id);

  perform app.capture_audit_event(
    v_issue.tenant_id, p_actor_auth_user_id, p_actor_label, 'add_vendor_performance_corrective_action',
    'app.vendor_performance_corrective_actions', v_action.id, 'success', null, null, jsonb_build_object('issue_id', p_issue_id)
  );

  return v_action;
end;
$$;

create function app.update_vendor_performance_corrective_action_status(p_action_id uuid, p_expected_version integer, p_status text, p_completion_note text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_performance_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_action app.vendor_performance_corrective_actions;
begin
  select * into v_action from app.vendor_performance_corrective_actions where id = p_action_id for update;
  if not found then
    raise exception 'vendor_performance_corrective_action_not_found: %', p_action_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_action.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_action.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_action.record_version <> p_expected_version then
    raise exception 'stale_version: vendor performance corrective action % expected version % but found %', p_action_id, p_expected_version, v_action.record_version
      using errcode = 'serialization_failure';
  end if;
  if p_status not in ('open', 'in_progress', 'completed', 'cancelled') then
    raise exception 'invalid_status: % is not one of open/in_progress/completed/cancelled', p_status using errcode = 'check_violation';
  end if;
  if v_action.status in ('completed', 'cancelled') then
    raise exception 'invalid_transition: vendor performance corrective action % is already %', p_action_id, v_action.status using errcode = 'check_violation';
  end if;
  if p_status = 'completed' and (p_completion_note is null or length(trim(p_completion_note)) = 0) then
    raise exception 'completion_note_required: a non-empty completion_note is required to complete a corrective action' using errcode = 'check_violation';
  end if;

  update app.vendor_performance_corrective_actions
  set status = p_status, completion_note = coalesce(p_completion_note, completion_note),
    completed_at = case when p_status = 'completed' then now() else completed_at end
  where id = p_action_id and record_version = p_expected_version
  returning * into v_action;
  if not found then
    raise exception 'stale_version: vendor performance corrective action % target row was concurrently modified (expected version %)', p_action_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_action.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_vendor_performance_corrective_action_status',
    'app.vendor_performance_corrective_actions', v_action.id, 'success', p_completion_note, null, jsonb_build_object('status', v_action.status)
  );

  return v_action;
end;
$$;

create function app.list_vendor_performance_corrective_actions(p_issue_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_performance_corrective_actions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_issue app.vendor_performance_issues;
begin
  select * into v_issue from app.vendor_performance_issues where id = p_issue_id;
  if not found or not app.has_active_tenant_membership(v_issue.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_performance_issue_not_found: %', p_issue_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_issue.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_issue.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_performance_corrective_actions where issue_id = p_issue_id order by created_at;
end;
$$;

-- ===========================================================================
-- 19. Manual adjustment -- design note 8.
-- ===========================================================================

create function app.request_vendor_kpi_manual_adjustment(
  p_scorecard_id uuid, p_kpi_code text, p_adjusted_normalized_score numeric, p_reason text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_kpi_manual_adjustments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_scorecard app.vendor_kpi_scorecards;
  v_line app.vendor_kpi_scorecard_lines;
  v_existing app.vendor_kpi_manual_adjustments;
  v_adjustment app.vendor_kpi_manual_adjustments;
begin
  select * into v_scorecard from app.vendor_kpi_scorecards where id = p_scorecard_id;
  if not found then
    raise exception 'vendor_kpi_scorecard_not_found: %', p_scorecard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_scorecard.tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_scorecard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to request a manual KPI adjustment' using errcode = 'check_violation';
  end if;
  if p_adjusted_normalized_score is null or p_adjusted_normalized_score < 0 or p_adjusted_normalized_score > 100 then
    raise exception 'invalid_score: adjusted_normalized_score must be between 0 and 100' using errcode = 'check_violation';
  end if;
  if v_scorecard.status <> 'published' then
    raise exception 'invalid_transition: vendor KPI scorecard % is % and cannot accept a manual adjustment', p_scorecard_id, v_scorecard.status
      using errcode = 'check_violation';
  end if;

  select * into v_line from app.vendor_kpi_scorecard_lines where scorecard_id = p_scorecard_id and kpi_code = p_kpi_code;
  if not found then
    raise exception 'vendor_kpi_scorecard_line_not_found: scorecard % has no line for kpi_code %', p_scorecard_id, p_kpi_code using errcode = 'no_data_found';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_kpi_manual_adjustments where tenant_id = v_scorecard.tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.scorecard_line_id is distinct from v_line.id or v_existing.adjusted_normalized_score is distinct from p_adjusted_normalized_score then
        raise exception 'idempotency_key_conflict: key % was already used for a different manual KPI adjustment', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_kpi_manual_adjustments (
      tenant_id, scorecard_id, scorecard_line_id, kpi_code, original_normalized_score, adjusted_normalized_score,
      reason, requested_by_auth_user_id, requested_by, idempotency_key, created_by
    ) values (
      v_scorecard.tenant_id, p_scorecard_id, v_line.id, p_kpi_code, v_line.normalized_score, p_adjusted_normalized_score,
      p_reason, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_adjustment;
  exception
    -- Nested to scope ONLY this INSERT (taxonomy C-02, same fix shape as app.create_
    -- vendor_kpi_definition_draft above) -- the pre-check's own idempotency_key_conflict
    -- raise above shares this errcode but lives OUTSIDE this block, so it is never
    -- caught here. A genuine pending-adjustment race (two concurrent requests against
    -- the SAME line, vendor_kpi_manual_adjustments_pending_unique) is what this handler
    -- actually exists for.
    when unique_violation then
      raise exception 'adjustment_already_pending: scorecard line % already has a pending manual adjustment', v_line.id using errcode = 'unique_violation';
  end;

  perform app.capture_audit_event(
    v_scorecard.tenant_id, p_actor_auth_user_id, p_actor_label, 'request_vendor_kpi_manual_adjustment',
    'app.vendor_kpi_manual_adjustments', v_adjustment.id, 'success', p_reason,
    jsonb_build_object('normalized_score', v_line.normalized_score), jsonb_build_object('requested_normalized_score', p_adjusted_normalized_score)
  );

  return v_adjustment;
end;
$$;

comment on function app.request_vendor_kpi_manual_adjustment is 'PRC-264: PRC:Edit (maker). published scorecards only. At most one pending adjustment per line (vendor_kpi_manual_adjustments_pending_unique); a genuine race is translated into the same typed adjustment_already_pending error, never a raw constraint-name leak. The race-recovery handler is nested to scope only the INSERT (taxonomy C-02 -- same class fixed in app.create_vendor_kpi_definition_draft, applied here too during this checkpoint''s own Tier B self-check).';

create function app.decide_vendor_kpi_manual_adjustment(p_adjustment_id uuid, p_expected_version integer, p_decision text, p_decision_notes text, p_actor_auth_user_id uuid, p_actor_label text)
returns app.vendor_kpi_manual_adjustments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_rbac app.rbac_decision;
  v_adjustment app.vendor_kpi_manual_adjustments;
  v_scorecard app.vendor_kpi_scorecards;
  v_line app.vendor_kpi_scorecard_lines;
  v_new_composite numeric;
  v_weighted_sum numeric := 0;
  v_computable_weight numeric := 0;
  v_row record;
begin
  select * into v_adjustment from app.vendor_kpi_manual_adjustments where id = p_adjustment_id for update;
  if not found then
    raise exception 'vendor_kpi_manual_adjustment_not_found: %', p_adjustment_id using errcode = 'no_data_found';
  end if;

  v_rbac := app.evaluate_permission(p_actor_auth_user_id, v_adjustment.tenant_id, 'PRC', 'Approve');
  if not v_rbac.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Approve (%) for tenant %', p_actor_auth_user_id, v_rbac.reason, v_adjustment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_adjustment.requested_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % requested manual adjustment % and may not also decide it', p_actor_auth_user_id, p_adjustment_id
      using errcode = 'insufficient_privilege';
  end if;
  if v_adjustment.record_version <> p_expected_version then
    raise exception 'stale_version: vendor KPI manual adjustment % expected version % but found %', p_adjustment_id, p_expected_version, v_adjustment.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_adjustment.status <> 'pending_approval' then
    raise exception 'invalid_transition: vendor KPI manual adjustment % is % and cannot be decided', p_adjustment_id, v_adjustment.status
      using errcode = 'check_violation';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision: % is not one of approved/rejected', p_decision using errcode = 'check_violation';
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'reason_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;

  update app.vendor_kpi_manual_adjustments
  set status = p_decision, decided_by_auth_user_id = p_actor_auth_user_id, decided_by = p_actor_label, decided_at = now(), decision_notes = p_decision_notes
  where id = p_adjustment_id and record_version = p_expected_version
  returning * into v_adjustment;
  if not found then
    raise exception 'stale_version: vendor KPI manual adjustment % target row was concurrently modified (expected version %)', p_adjustment_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  if p_decision = 'approved' then
    select * into v_scorecard from app.vendor_kpi_scorecards where id = v_adjustment.scorecard_id for update;

    update app.vendor_kpi_scorecard_lines
    set normalized_score = v_adjustment.adjusted_normalized_score,
      band = app._band_for_score(v_adjustment.adjusted_normalized_score, band_thresholds_snapshot),
      is_computable = true, adjusted = true
    where id = v_adjustment.scorecard_line_id
    returning * into v_line;

    for v_row in select weight_snapshot, normalized_score, is_computable from app.vendor_kpi_scorecard_lines where scorecard_id = v_scorecard.id loop
      if v_row.is_computable then
        v_computable_weight := v_computable_weight + v_row.weight_snapshot;
        v_weighted_sum := v_weighted_sum + (v_row.weight_snapshot * v_row.normalized_score);
      end if;
    end loop;
    v_new_composite := round(v_weighted_sum / nullif(v_computable_weight, 0), 2);

    update app.vendor_kpi_scorecards
    set composite_score = v_new_composite, band = app._band_for_score(v_new_composite, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb), computable_weight_total = v_computable_weight
    where id = v_scorecard.id and record_version = v_scorecard.record_version;
    if not found then
      raise exception 'stale_version: vendor KPI scorecard % was concurrently modified while applying an adjustment', v_scorecard.id using errcode = 'serialization_failure';
    end if;

    perform app.capture_audit_event(
      v_adjustment.tenant_id, p_actor_auth_user_id, p_actor_label, 'apply_vendor_kpi_manual_adjustment',
      'app.vendor_kpi_scorecards', v_scorecard.id, 'success', p_decision_notes,
      jsonb_build_object('composite_score', v_scorecard.composite_score, 'band', v_scorecard.band),
      jsonb_build_object('composite_score', v_new_composite, 'band', app._band_for_score(v_new_composite, '{"excellent": 90, "good": 75, "watch": 60}'::jsonb))
    );
  end if;

  perform app.capture_audit_event(
    v_adjustment.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_kpi_manual_adjustment',
    'app.vendor_kpi_manual_adjustments', v_adjustment.id, 'success', p_decision_notes, null, jsonb_build_object('status', v_adjustment.status)
  );

  return v_adjustment;
end;
$$;

comment on function app.decide_vendor_kpi_manual_adjustment is
  'PRC-264: PRC:Approve (checker), self-approval blocked (requested_by <> decided_by). On approval, mutates the CURRENT published scorecard''s line + composite_score/band in place under a record_version guard (design note 8), never mints a redundant new scorecard version -- app.vendor_kpi_manual_adjustments itself is the permanent before/after evidence (original_normalized_score vs adjusted_normalized_score, plus this function''s own capture_audit_event before/after on the scorecard).';

create function app.get_vendor_kpi_manual_adjustment(p_adjustment_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_kpi_manual_adjustments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_adjustment app.vendor_kpi_manual_adjustments;
begin
  select * into v_adjustment from app.vendor_kpi_manual_adjustments where id = p_adjustment_id;
  if not found or not app.has_active_tenant_membership(v_adjustment.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_manual_adjustment_not_found: %', p_adjustment_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_adjustment.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_adjustment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_adjustment;
end;
$$;

create function app.list_vendor_kpi_manual_adjustments(p_scorecard_id uuid, p_actor_auth_user_id uuid)
returns setof app.vendor_kpi_manual_adjustments
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_scorecard app.vendor_kpi_scorecards;
begin
  select * into v_scorecard from app.vendor_kpi_scorecards where id = p_scorecard_id;
  if not found or not app.has_active_tenant_membership(v_scorecard.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_kpi_scorecard_not_found: %', p_scorecard_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_scorecard.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_scorecard.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query select * from app.vendor_kpi_manual_adjustments where scorecard_id = p_scorecard_id order by requested_at desc;
end;
$$;

-- ===========================================================================
-- 20. Governed lifecycle action -- design note 9.
-- ===========================================================================

create function app.evaluate_vendor_lifecycle_recommendation(
  p_tenant_id uuid, p_vendor_master_id uuid, p_scorecard_id uuid, p_override_action text, p_rationale text,
  p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_lifecycle_recommendations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_vendor app.vendor_profiles;
  v_scorecard app.vendor_kpi_scorecards;
  v_existing app.vendor_lifecycle_recommendations;
  v_recommendation app.vendor_lifecycle_recommendations;
  v_action text;
  v_rationale text;
begin
  -- C-05: permission check before the vendor existence lookup (see raise_vendor_kpi_source_dispute's own comment above for the precedent this follows).
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_vendor from app.vendor_profiles where master_record_id = p_vendor_master_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'vendor_profile_not_found: %', p_vendor_master_id using errcode = 'no_data_found';
  end if;

  if p_scorecard_id is not null then
    select * into v_scorecard from app.vendor_kpi_scorecards where id = p_scorecard_id and tenant_id = p_tenant_id and vendor_master_id = p_vendor_master_id;
    if not found then
      raise exception 'vendor_kpi_scorecard_not_found: % does not belong to vendor % in tenant %', p_scorecard_id, p_vendor_master_id, p_tenant_id using errcode = 'no_data_found';
    end if;
  end if;

  if p_override_action is not null then
    if p_override_action not in ('none', 'watch', 'suspend', 'blacklist', 'reactivate') then
      raise exception 'invalid_action: % is not one of none/watch/suspend/blacklist/reactivate', p_override_action using errcode = 'check_violation';
    end if;
    if p_rationale is null or length(trim(p_rationale)) = 0 then
      raise exception 'reason_required: a non-empty rationale is required for an analyst-overridden lifecycle recommendation' using errcode = 'check_violation';
    end if;
    v_action := p_override_action;
    v_rationale := p_rationale;
  elsif v_scorecard.id is not null then
    if v_scorecard.band = 'poor' then
      v_action := 'suspend';
      v_rationale := format('System-derived: scorecard %s composite_score=%s band=poor for window %s to %s', v_scorecard.id, v_scorecard.composite_score, v_scorecard.window_start, v_scorecard.window_end);
    else
      v_action := 'none';
      v_rationale := format('System-derived: scorecard %s band=%s does not meet the poor threshold that would recommend suspension', v_scorecard.id, v_scorecard.band);
    end if;
  else
    raise exception 'basis_required: either p_scorecard_id or a p_override_action with a rationale is required' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    select * into v_existing from app.vendor_lifecycle_recommendations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
    if found then
      if v_existing.vendor_master_id is distinct from p_vendor_master_id or v_existing.recommended_action is distinct from v_action
        or v_existing.scorecard_id is distinct from p_scorecard_id
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different vendor lifecycle recommendation', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_existing;
    end if;
  end if;

  begin
    insert into app.vendor_lifecycle_recommendations (
      tenant_id, vendor_master_id, scorecard_id, recommended_action, recommended_rationale, recommended_by_auth_user_id, recommended_by, idempotency_key, created_by
    ) values (
      p_tenant_id, p_vendor_master_id, p_scorecard_id, v_action, v_rationale, p_actor_auth_user_id, p_actor_label, p_idempotency_key, p_actor_label
    )
    returning * into v_recommendation;
  exception
    -- Race-recovery only, nested to scope ONLY this INSERT (taxonomy C-02).
    when unique_violation then
      select * into v_recommendation from app.vendor_lifecycle_recommendations where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      if v_recommendation.vendor_master_id is distinct from p_vendor_master_id or v_recommendation.recommended_action is distinct from v_action
        or v_recommendation.scorecard_id is distinct from p_scorecard_id
      then
        raise exception 'idempotency_key_conflict: key % was already used for a different vendor lifecycle recommendation', p_idempotency_key using errcode = 'unique_violation';
      end if;
      return v_recommendation;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_vendor_lifecycle_recommendation',
    'app.vendor_lifecycle_recommendations', v_recommendation.id, 'success', null, null, jsonb_build_object('recommended_action', v_action)
  );

  return v_recommendation;
end;
$$;

comment on function app.evaluate_vendor_lifecycle_recommendation is
  'PRC-264: PRC:Edit. NEVER changes app.vendor_profiles.lifecycle_status itself (design note 9) -- purely a recommendation row. Defaults to band=poor -> suspend / else none when driven by a scorecard; an analyst may override with any of the five actions given a mandatory rationale (e.g. proposing blacklist off a severe issue with no fresh scorecard basis).';

create function app.decide_vendor_lifecycle_recommendation(
  p_recommendation_id uuid, p_expected_version integer, p_decided_action text, p_decision_notes text, p_evidence_ref text,
  p_actor_auth_user_id uuid, p_actor_label text
)
returns app.vendor_lifecycle_recommendations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_recommendation app.vendor_lifecycle_recommendations;
  v_vendor app.vendor_profiles;
begin
  select * into v_recommendation from app.vendor_lifecycle_recommendations where id = p_recommendation_id for update;
  if not found then
    raise exception 'vendor_lifecycle_recommendation_not_found: %', p_recommendation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_recommendation.tenant_id, 'PRC', 'Override');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Override (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_recommendation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Maker-checker, C-18: this is the highest-stakes decision this capability exposes (it can
  -- suspend/blacklist a vendor's eligibility), so self-approval is blocked exactly like the
  -- lower-stakes dispute/manual-adjustment decisions above, even though it is structurally
  -- possible for one actor to hold both PRC:Edit (evaluate) and PRC:Override (decide).
  if v_recommendation.recommended_by_auth_user_id is not null and v_recommendation.recommended_by_auth_user_id = p_actor_auth_user_id then
    raise exception 'self_approval_not_allowed: identity % evaluated recommendation % and may not also decide it', p_actor_auth_user_id, p_recommendation_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_recommendation.record_version <> p_expected_version then
    raise exception 'stale_version: vendor lifecycle recommendation % expected version % but found %', p_recommendation_id, p_expected_version, v_recommendation.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_recommendation.status <> 'pending' then
    raise exception 'invalid_transition: vendor lifecycle recommendation % is % and cannot be decided', p_recommendation_id, v_recommendation.status
      using errcode = 'check_violation';
  end if;
  if p_decided_action not in ('none', 'watch', 'suspend', 'blacklist', 'reactivate') then
    raise exception 'invalid_action: % is not one of none/watch/suspend/blacklist/reactivate', p_decided_action using errcode = 'check_violation';
  end if;
  if p_decision_notes is null or length(trim(p_decision_notes)) = 0 then
    raise exception 'reason_required: a non-empty decision_notes is required' using errcode = 'check_violation';
  end if;
  if p_decided_action = 'blacklist' and (p_evidence_ref is null or length(trim(p_evidence_ref)) = 0) then
    raise exception 'evidence_required: evidence is required to decide a blacklist lifecycle recommendation' using errcode = 'check_violation';
  end if;

  update app.vendor_lifecycle_recommendations
  set status = 'decided', decided_action = p_decided_action, decided_by_auth_user_id = p_actor_auth_user_id, decided_by = p_actor_label,
    decided_at = now(), decision_notes = p_decision_notes, evidence_ref = p_evidence_ref
  where id = p_recommendation_id and record_version = p_expected_version
  returning * into v_recommendation;
  if not found then
    raise exception 'stale_version: vendor lifecycle recommendation % target row was concurrently modified (expected version %)', p_recommendation_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- The one, and only, path that ever calls a real PRC-251 vendor-lifecycle RPC
  -- (design note 9). If the nested call raises (e.g. the vendor is no longer in the
  -- required state), the ENTIRE transaction -- including the status='decided' update
  -- just above -- rolls back, so a recommendation can never be left "decided but not
  -- executed" (no exception handler here catches it).
  if p_decided_action in ('suspend', 'blacklist', 'reactivate') then
    select * into v_vendor from app.vendor_profiles where master_record_id = v_recommendation.vendor_master_id;
    if p_decided_action = 'suspend' then
      perform app.suspend_vendor_profile(v_vendor.master_record_id, v_vendor.record_version, p_decision_notes, p_actor_auth_user_id, p_actor_label);
    elsif p_decided_action = 'blacklist' then
      perform app.blacklist_vendor_profile(v_vendor.master_record_id, v_vendor.record_version, p_decision_notes, p_evidence_ref, p_actor_auth_user_id, p_actor_label);
    elsif p_decided_action = 'reactivate' then
      perform app.reactivate_vendor_profile(v_vendor.master_record_id, v_vendor.record_version, p_actor_auth_user_id, p_actor_label);
    end if;

    update app.vendor_lifecycle_recommendations set executed = true, executed_at = now() where id = p_recommendation_id;
  end if;

  perform app.capture_audit_event(
    v_recommendation.tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_vendor_lifecycle_recommendation',
    'app.vendor_lifecycle_recommendations', v_recommendation.id, 'success', p_decision_notes, null,
    jsonb_build_object('decided_action', p_decided_action, 'executed', p_decided_action in ('suspend', 'blacklist', 'reactivate'))
  );

  select * into v_recommendation from app.vendor_lifecycle_recommendations where id = p_recommendation_id;
  return v_recommendation;
end;
$$;

comment on function app.decide_vendor_lifecycle_recommendation is
  'PRC-264: PRC:Override -- the SAME authority app.suspend_vendor_profile/app.blacklist_vendor_profile/app.reactivate_vendor_profile themselves already require of the identical actor, checked twice by design (once here, once again inside the nested PRC-251 call, never weakened). none/watch never call PRC-251 at all. Human-governed by construction (Prompt 264 §24 "System may recommend; authorized humans decide").';

create function app.get_vendor_lifecycle_recommendation(p_recommendation_id uuid, p_actor_auth_user_id uuid)
returns app.vendor_lifecycle_recommendations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_recommendation app.vendor_lifecycle_recommendations;
begin
  select * into v_recommendation from app.vendor_lifecycle_recommendations where id = p_recommendation_id;
  if not found or not app.has_active_tenant_membership(v_recommendation.tenant_id, p_actor_auth_user_id) then
    raise exception 'vendor_lifecycle_recommendation_not_found: %', p_recommendation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_recommendation.tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_recommendation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return v_recommendation;
end;
$$;

create function app.list_vendor_lifecycle_recommendations(p_tenant_id uuid, p_vendor_master_id uuid, p_status text, p_actor_auth_user_id uuid, p_limit integer default 50)
returns setof app.vendor_lifecycle_recommendations
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
begin
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  return query
  select * from app.vendor_lifecycle_recommendations
  where tenant_id = p_tenant_id and (p_vendor_master_id is null or vendor_master_id = p_vendor_master_id) and (p_status is null or status = p_status)
  order by recommended_at desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

-- ===========================================================================
-- 21. RLS. Tenant-scoped select, matching every sibling PRC-25x/26x table's own
--     `has_active_tenant_membership(tenant_id) and not actor_holds_customer_user_layer
--     (tenant_id)) or is_supreme_admin()` shape exactly.
-- ===========================================================================

alter table app.vendor_kpi_definitions enable row level security;
alter table app.vendor_kpi_source_disputes enable row level security;
alter table app.vendor_kpi_measurement_runs enable row level security;
alter table app.vendor_kpi_metric_values enable row level security;
alter table app.vendor_kpi_scorecards enable row level security;
alter table app.vendor_kpi_scorecard_lines enable row level security;
alter table app.vendor_performance_issues enable row level security;
alter table app.vendor_performance_corrective_actions enable row level security;
alter table app.vendor_kpi_manual_adjustments enable row level security;
alter table app.vendor_lifecycle_recommendations enable row level security;

create policy vendor_kpi_definitions_select_scoped on app.vendor_kpi_definitions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_kpi_source_disputes_select_scoped on app.vendor_kpi_source_disputes
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_kpi_measurement_runs_select_scoped on app.vendor_kpi_measurement_runs
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_kpi_metric_values_select_scoped on app.vendor_kpi_metric_values
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_kpi_scorecards_select_scoped on app.vendor_kpi_scorecards
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_kpi_scorecard_lines_select_scoped on app.vendor_kpi_scorecard_lines
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_performance_issues_select_scoped on app.vendor_performance_issues
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_performance_corrective_actions_select_scoped on app.vendor_performance_corrective_actions
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_kpi_manual_adjustments_select_scoped on app.vendor_kpi_manual_adjustments
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

create policy vendor_lifecycle_recommendations_select_scoped on app.vendor_lifecycle_recommendations
  for select to authenticated
  using ((app.has_active_tenant_membership(tenant_id) and not app.actor_holds_customer_user_layer(tenant_id)) or app.is_supreme_admin());

-- ===========================================================================
-- 22. Grants. Base-table select is tenant-RLS-scoped but unrestricted by column --
--     matching this exact phase's own established app.claim_responsibility_reviews
--     convention (design note 3); no column here is ever a raw currency amount, so this
--     is a strictly lower-risk posture than that precedent, not a new gap. Masking
--     (contributing_source_ids) is enforced at the RPC layer, in
--     app.get_vendor_kpi_scorecard_drilldown, the one place it is ever read.
-- ===========================================================================

revoke execute on all functions in schema app from public;

grant select on
  app.vendor_kpi_definitions, app.vendor_kpi_source_disputes, app.vendor_kpi_measurement_runs, app.vendor_kpi_metric_values,
  app.vendor_kpi_scorecards, app.vendor_kpi_scorecard_lines, app.vendor_performance_issues, app.vendor_performance_corrective_actions,
  app.vendor_kpi_manual_adjustments, app.vendor_lifecycle_recommendations
  to authenticated, service_role;
grant insert, update on
  app.vendor_kpi_definitions, app.vendor_kpi_source_disputes, app.vendor_kpi_measurement_runs, app.vendor_kpi_metric_values,
  app.vendor_kpi_scorecards, app.vendor_kpi_scorecard_lines, app.vendor_performance_issues, app.vendor_performance_corrective_actions,
  app.vendor_kpi_manual_adjustments, app.vendor_lifecycle_recommendations
  to service_role;

grant execute on function app.validate_vendor_kpi_band_thresholds(jsonb) to service_role;
grant execute on function app.mask_vendor_kpi_source_evidence(jsonb, boolean) to authenticated, service_role;

grant execute on function app.create_vendor_kpi_definition_draft(uuid, text, text, text, integer, integer, numeric, text, numeric, text, jsonb, jsonb, integer, boolean, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_kpi_definition_draft(uuid, integer, text, text, integer, integer, numeric, text, numeric, text, jsonb, jsonb, integer, boolean, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_vendor_kpi_definition(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.archive_vendor_kpi_definition(uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_kpi_definition(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_kpi_definitions(uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.list_vendor_kpi_definition_versions(uuid, text, uuid) to authenticated, service_role;

grant execute on function app.raise_vendor_kpi_source_dispute(uuid, uuid, text, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_kpi_source_dispute(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_kpi_source_dispute(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_kpi_source_disputes(uuid, uuid, text, uuid) to authenticated, service_role;

grant execute on function app.calculate_vendor_kpi_metrics(uuid, uuid, timestamptz, timestamptz, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.publish_vendor_kpi_scorecard(uuid, uuid, timestamptz, timestamptz, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_kpi_scorecard(uuid, uuid) to authenticated, service_role;
grant execute on function app.get_vendor_kpi_scorecard_drilldown(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_kpi_scorecards(uuid, uuid, uuid, integer) to authenticated, service_role;
grant execute on function app.get_vendor_kpi_measurement_run(uuid, uuid) to authenticated, service_role;

grant execute on function app.raise_vendor_performance_issue(uuid, uuid, uuid, text, text, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_performance_issue_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_performance_issue(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_performance_issues(uuid, uuid, text, uuid, integer) to authenticated, service_role;
grant execute on function app.add_vendor_performance_corrective_action(uuid, text, text, date, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_vendor_performance_corrective_action_status(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.list_vendor_performance_corrective_actions(uuid, uuid) to authenticated, service_role;

grant execute on function app.request_vendor_kpi_manual_adjustment(uuid, text, numeric, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_kpi_manual_adjustment(uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_kpi_manual_adjustment(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_kpi_manual_adjustments(uuid, uuid) to authenticated, service_role;

grant execute on function app.evaluate_vendor_lifecycle_recommendation(uuid, uuid, uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.decide_vendor_lifecycle_recommendation(uuid, integer, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_vendor_lifecycle_recommendation(uuid, uuid) to authenticated, service_role;
grant execute on function app.list_vendor_lifecycle_recommendations(uuid, uuid, text, uuid, integer) to authenticated, service_role;

grant execute on function app.accept_vendor_assignment_invitation(uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decline_vendor_assignment_invitation(uuid, integer, text, uuid, text) to authenticated, service_role;
