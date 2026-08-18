-- Phase 8 capability CPL-322 (CG-S13-CPL-024, Prompt 322, "Expiry and Fraud
-- Prevention") -- the THIRD prompt of Batch 5 (CPL-320..323), and the
-- SEVENTH Loyalty-domain capability in this repository (ADR-0024 Part D).
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-
-- pattern.md (Parts A/B/D); docs/build-log/phase-08/CPL-317.md, CPL-318.md,
-- CPL-319.md, CPL-320.md, CPL-321.md and their own migrations
-- (20260801190000/200000/210000/220000/230000) IN FULL; supabase/migrations/
-- 20260731160000_create_ticket_escalation.sql (HRT-291) IN FULL -- this
-- checkpoint's own two directly-applicable precedents (a batch/sweep RPC
-- backed by a real app.jobs row, and an authority/reason/expiry-gated
-- suppression table with at-most-one-active-row-per-target and
-- auto-revoke-on-next-check) -- before writing any of this file.
--
-- This migration READS (never writes) app.loyalty_accounts/app.loyalty_
-- programs (CPL-316), app.loyalty_account_tier_holds (CPL-317, COMPOSED via
-- app.hold_loyalty_account_tier_benefits/app.release_loyalty_account_tier_
-- benefits -- never a direct table write, and never a second, competing
-- account-hold table), and COMPOSES app.expire_loyalty_point_lots (CPL-318)
-- and app.expire_loyalty_benefit_entitlements (CPL-319) -- both already
-- exist, idempotent, tenant-wide scans; this migration never reimplements
-- either's own expiry logic. It builds two wholly NEW tables of its own
-- (app.loyalty_fraud_review_cases, app.loyalty_fraud_review_suppressions)
-- plus a widened app.jobs.job_type CHECK constraint (the established
-- drop/add-constraint pattern, never a bare narrowing ALTER).
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **`app.run_loyalty_expiry_sweep` mirrors `app.run_ticket_escalation_
--    evaluation_batch` (HRT-291)/`app.run_ticket_sla_evaluation_batch`
--    (HRT-289) EXACTLY in shape -- a real app.jobs row tracked through the
--    actual PLT-132 lifecycle (enqueue -> self-claim -> loop -> complete),
--    idempotent per (tenant, run_label) at the JOB level via app.enqueue_
--    job's own real `unique(tenant_id, idempotency_key)` constraint and its
--    own real `exception when unique_violation` handler.** `p_run_label`
--    (my own disclosed design call, a genuine 5th parameter beyond this
--    prompt's own literal 4-parameter signature) defaults to the calendar
--    day of `p_as_of` (`to_char(v_as_of, 'YYYY-MM-DD')`) when not supplied
--    -- "idempotent per tenant per calendar day, or per a caller-supplied
--    run label," this prompt's own literal instruction, both satisfied by
--    the SAME parameter: the default gives calendar-day idempotency for
--    free; an explicit label lets a deliberate supplemental same-day rerun
--    happen under its own distinct idempotency key. Storm control (two
--    genuinely CONCURRENT overlapping calls for the SAME tenant+run_label
--    never double-processing) is not a separate mechanism bolted on top --
--    it is the SAME underlying guarantee `app.run_ticket_escalation_
--    evaluation_batch`/`app.run_ticket_sla_evaluation_batch` already rely
--    on, worked through explicitly here rather than merely assumed: a
--    SECOND concurrent transaction's own `insert into app.jobs` (inside
--    `app.enqueue_job`) BLOCKS on the identical `(tenant_id, idempotency_
--    key)` unique index until the FIRST transaction commits (the entire
--    sweep -- enqueue, claim, both expiry compositions, and completion --
--    runs inside ONE transaction per top-level call, so nothing commits
--    until the whole thing finishes); once the first commits, the second's
--    insert fails `unique_violation`, its exception handler re-selects the
--    row (now genuinely `completed`), and this function's own `if v_job.
--    status = 'pending'` guard correctly skips re-running the sweep body --
--    a REAL serialize-then-no-op outcome, not a race, live-proven with a
--    genuine two-process concurrent race in this checkpoint's own db-test
--    (reusing `scripts/db-tests/wms-picking-concurrency-helper.sh`, CPL-318/
--    320/321's own established two-psql-process concurrency helper).
--    Composes `app.expire_loyalty_point_lots`/`app.expire_loyalty_benefit_
--    entitlements` (both already real, complete, idempotent, tenant-wide
--    scans) -- never reimplements either's own scan/posting logic. Real
--    counts (`lots_expired_count`/`entitlements_expired_count`) are counted
--    from each composed function's own actually-returned row set (`select
--    count(*) from app.expire_loyalty_point_lots(...)`, not a guessed or
--    hardcoded number) and recorded ON THE COMPLETED JOB ROW ITSELF -- this
--    prompt's own explicit ask -- via a real `update app.jobs set payload =
--    payload || jsonb_build_object(...)`, since `app.jobs` has no dedicated
--    result-count column of its own and its existing `total_rows`/
--    `processed_rows`/`valid_row_count`/`invalid_row_count` columns are
--    grep-confirmed used ONLY by import/export-flavored bulk-row-commit call
--    sites elsewhere in this repository (never a generic domain-batch count)
--    -- reusing the ALREADY-JSONB, ALREADY-NOT-NULL, ALREADY-free-form
--    `payload` column (set once at enqueue time by every prior job-type
--    adopter, extended here additively after the fact) is the smaller,
--    disclosed choice over adding a new column to a repository-wide shared
--    table for one job type's own result shape. `app.list_loyalty_expiry_
--    runs` reads it back. **No live scheduler exists anywhere in this
--    repository (the SAME disclosed `NOT_RUN` class PLT-123/125/132 and
--    HRT-289/291 already established) -- this RPC is the real, callable,
--    tested entry point a future scheduler would invoke periodically,**
--    closing ISS-2026-126/127/128/129's own "on-demand/staff-triggered
--    only" precedent's own scheduling gap for point-lot/entitlement expiry
--    specifically (the underlying expiry PRIMITIVES were always real and
--    complete; only the periodic-invocation wiring was ever missing).
-- 2. **`'loyalty_expiry_sweep'` is a genuinely NEW job_type literal, not a
--    reuse of the pre-existing, speculatively-seeded `'loyalty_expiration'`
--    value** (`app.jobs`' own CHECK constraint has carried `'loyalty_
--    expiration'` since PLT-132's own original migration, 20260719180000 --
--    grep-confirmed it has NEVER been the target of a real `app.enqueue_
--    job`/`app.dispatch_event_as_job` call anywhere in this repository,
--    including nowhere in this Loyalty domain's own five prior checkpoints,
--    CPL-316..321, none of which ever created an `app.jobs` row of ANY
--    type). Disclosed choice, not an oversight: this checkpoint's own job
--    composes TWO distinct primitives (point-lot expiry AND benefit-
--    entitlement expiry) in one sweep, a more specific semantic than the
--    old, generic, never-realized placeholder name; mirrors this exact
--    domain's own established precedent of adding increasingly specific new
--    literals even where a broader generic one already existed
--    (`'ticket_sla_evaluation'`/`'kb_article_expiry'`/`'ticket_escalation_
--    evaluation'` were all added by HRT-289/290/291 despite `'notification_
--    batch'`/`'dashboard_refresh'` already being valid, generic-sounding
--    values). Widened via the established drop/add-constraint pattern
--    (grep-verified against every `drop constraint jobs_job_type_check`
--    migration to date, HRT-291's own migration the most recent, before
--    finalizing this file) -- the full CURRENT list carried forward
--    verbatim plus this checkpoint's own one new value, never a narrowing
--    ALTER, never re-derived from a single earlier migration in isolation
--    (CPL-317's own self-found-and-fixed sibling defect class, applied
--    proactively here). `app.generic_job_types()` (the ATW-031/ISS-2026-012
--    single-source-of-truth function `app.enqueue_job`/`app.dispatch_
--    event_as_job` both already call) is widened identically, in the SAME
--    migration, per that hardening's own explicit requirement.
-- 3. **Fraud hold: the account-level primitive is composed, NEVER
--    reinvented.** `app.open_loyalty_fraud_review_case` composes `app.hold_
--    loyalty_account_tier_benefits` (CPL-317); `app.decide_loyalty_fraud_
--    review_case`'s own `'clear'` branch composes `app.release_loyalty_
--    account_tier_benefits` (CPL-317). Neither function ever writes `app.
--    loyalty_account_tier_holds` directly. This is the SAME table CPL-321's
--    own `app.submit_loyalty_redemption`/`app.decide_loyalty_redemption`
--    already read directly (`select coalesce(is_held, false) from app.
--    loyalty_account_tier_holds where ...`) as the account-wide "is this
--    account blocked from redeeming" gate -- a fraud hold this checkpoint
--    opens is therefore IMMEDIATELY, structurally effective against
--    redemption, with zero new coupling code anywhere, live-proven in this
--    checkpoint's own db-test (open a case on an account, then attempt
--    `app.submit_loyalty_redemption` against that SAME account, live cross-
--    prompt regression proof). It is ALSO the SAME table CPL-317's own
--    customer-facing `app.list_customer_portal_loyalty_tier_cards` already
--    reads to suppress tier-benefit display with a generic customer-safe
--    notice -- a fraud hold this checkpoint opens is therefore ALSO
--    immediately visible on the ALREADY-SHIPPED, UNMODIFIED `customer-
--    loyalty-tier` page, zero new code there either.
-- 4. **Authority for `app.open_loyalty_fraud_review_case`: `LYL:Configure`,
--    the SAME elevated authority its own composed `app.hold_loyalty_
--    account_tier_benefits` independently requires -- deliberately NOT a
--    lower `LYL:Edit` outer gate with a nested re-check (CPL-318 design
--    decision 16 / CPL-321 design decision 14's own established shape).**
--    Reasoned explicitly: opening a case is not a "lightweight, provisional"
--    action in EFFECT, whatever its name suggests -- it immediately applies
--    a real, non-trivial, account-wide restriction (blocks ALL redemption
--    activity, tier-benefit display, per decision 3). Gating the outer
--    action at a LOWER authority than what its own inner composition needs
--    would only ever succeed for an actor who ALSO independently holds the
--    higher authority anyway (since the composed call re-checks it), so a
--    lower outer gate would be pure theater -- worse, it would let an
--    `LYL:Edit`-only actor's call fail confusingly deep inside a nested
--    composition after already inserting a real case row, reopening exactly
--    the "partial success, unclear failure point" shape CPL-321's own
--    design decision 5 worked hard to avoid for a materially different
--    (RBAC-widening) reason. Matching outer/inner authority sidesteps the
--    whole class of problem. `app.claim_loyalty_fraud_review_case` (a
--    disclosed 3rd function beyond this prompt's own two literally-named
--    RPCs, decision 6) and the tenant-wide expiry sweep both stay at the
--    ordinary `LYL:Edit` mirroring their own composed primitives' identical
--    gate (no mismatch there). `app.decide_loyalty_fraud_review_case`
--    (confirm/clear) is `LYL:Configure` per this prompt's own explicit
--    instruction ("governance-grade, matching CPL-317/318/319's own
--    convention for irreversible/high-stakes decisions").
-- 5. **`app.loyalty_fraud_review_cases.status`: `open` -> (`under_review`)
--    -> `confirmed`/`cleared`, mirroring the maker-checker discipline
--    already established across this batch (PRC-264 precedent, reused
--    throughout Loyalty) -- but this is NOT a maker-checker pair in the
--    literal sense (one actor requests, a DIFFERENT actor decides,
--    self-approval blocked).** This prompt's own alternative flow reads
--    "a rule/signal-triggered hold may be system-created as a PROVISIONAL/
--    pending-review state, but any LASTING punitive/confirmed outcome
--    requires one real human reviewer's own RPC call with a mandatory
--    reason" -- the maker-checker ANALOGY that matters here is SYSTEM/RULE
--    (opens, provisional) vs. HUMAN REVIEWER (decides, final), not two
--    DIFFERENT humans. No self-approval block is built for THIS reason: no
--    live rule/signal-detection engine exists anywhere in this repository
--    (source prompt business rule 24: "predictive fraud depth remains Step
--    14") to open a case autonomously in this checkpoint, so every
--    `open_loyalty_fraud_review_case` call in practice today is itself
--    staff-initiated (`opened_by = p_actor_label`, a real staff actor's own
--    label) -- the SAME staff member deciding their OWN just-opened case is
--    a real, if narrow, gap this checkpoint does not close (unlike CPL-318's
--    own genuine two-different-humans maker-checker, which DOES block
--    self-approval because BOTH roles are always human there). Disclosed as
--    `ISS-2026-133` item 1, not silently assumed safe.
-- 6. **`app.claim_loyalty_fraud_review_case` (open -> under_review) is a
--    disclosed 3rd function, beyond `open_loyalty_fraud_review_case`/
--    `decide_loyalty_fraud_review_case` this prompt's own literal text names
--    -- mirrors CPL-320's own disclosed `resume_loyalty_reward` 6th-function
--    precedent exactly.** `status` genuinely covering `under_review` "at
--    minimum" (this prompt's own literal instruction) is meaningless if
--    nothing ever transitions a case there -- `decide_loyalty_fraud_review_
--    case` itself accepts a decision from EITHER `open` OR `under_review`
--    (claiming first is optional operational bookkeeping, "a reviewer is
--    now actively looking at this," never a required gate before deciding),
--    so `under_review` is genuinely reachable without being load-bearing for
--    anything else.
-- 7. **Suppression/cooldown mirrors `app.ticket_escalation_suppressions`'
--    own EXACT shape (HRT-291 decision 11)**: `app.loyalty_fraud_review_
--    suppressions` -- `LYL:Configure`-gated (the SAME elevated bar this
--    domain already uses for every governance-grade Loyalty action, the
--    direct analogue of HRT-291's own "TKT:Assign, a materially higher bar
--    than plain is_ticket_staff" reasoning, since LYL carries no distinct
--    `Assign` action of its own), mandatory non-empty reason, mandatory
--    future `expires_at`, at most one non-revoked row per `loyalty_
--    account_id` at a time (a real partial unique index, `lfrs_active_
--    unique`), and an already-expired-but-unrevoked row auto-revoked
--    (`revoked_reason = 'expired'`) the NEXT time it is checked -- which,
--    for this checkpoint, is the single place a suppression's presence ever
--    actually matters: inside `app.open_loyalty_fraud_review_case` itself,
--    immediately before attempting to insert a new case. NEVER hides
--    `app.loyalty_fraud_review_cases`/`app.loyalty_account_tier_holds`'
--    own history -- a suppression gates only whether a NEW case may be
--    opened, exactly mirroring HRT-291's own "suppression only gates
--    whether a NEW level may auto-trigger, never what compliance reporting
--    can see" business rule, word-for-word the same "suppression/cooldown"
--    language this prompt's own source spec business-rules section uses.
--    One deliberate, disclosed departure from the HRT-291 precedent's own
--    literal timestamp choice: `clock_timestamp()`, never `now()`,
--    throughout this table and its two owning functions (HRT-291 itself
--    used `now()` for `created_at`/`revoked_at` -- an earlier-Phase, pre-
--    CPL-315 migration) -- this domain's own already-established, uniformly
--    applied convention since CPL-315/317, carried forward here even though
--    the precedent being mirrored predates it.
-- 8. **Entitlement-level fraud hold: NOT built, account-level coverage is
--    sufficient for this checkpoint, disclosed rather than silently
--    skipped.** Three concrete reasons: (a) an account-level hold ALREADY
--    blocks every redemption for the account (decision 3) -- any
--    investigation broad enough to warrant halting activity is already
--    fully covered; (b) CPL-319's own `app.hold_loyalty_benefit_
--    entitlement`/`app.release_loyalty_benefit_entitlement_hold` ALREADY
--    exist, are ALREADY independently staff-callable (`LYL:Configure`)
--    TODAY via the already-shipped `admin/loyalty-benefits` UI, with zero
--    new code needed from this checkpoint for a staff member to hold ONE
--    suspicious voucher/cashback/discount row directly; (c) building a
--    SECOND, parallel case-and-decide review-case mechanism scoped to
--    individual entitlements (a different target-row shape, a different
--    composed pair) would meaningfully widen this migration's already-
--    substantial scope (expiry sweep + account-level case/hold/suppression
--    + this checkpoint's own required tests) with no concrete, disclosed
--    business need calling for it at this checkpoint. Disclosed as
--    `ISS-2026-133` item 2.
-- 9. **Redaction (business rule + security impact: "fraud signals and
--    thresholds are restricted internal data... never exposed to a
--    customer_user caller, not even in an error message").**
--    `risk_signal_type`/`risk_signal_detail`/`review_reason`/`reviewed_by`
--    exist ONLY on `app.loyalty_fraud_review_cases`, read ONLY by the three
--    `LYL:View`-gated staff RPCs. `app.list_customer_portal_loyalty_
--    account_hold_status` (the one customer-facing read this checkpoint
--    adds) never references `app.loyalty_fraud_review_cases` AT ALL --
--    structurally, grep-provably impossible to leak any fraud-review field
--    through it, not merely a query-level projection choice -- returning
--    ONLY `is_on_hold`/a generic `hold_notice` sourced from `app.loyalty_
--    account_tier_holds.is_held` (mirrors CPL-317/319's own already-proven
--    generic hold message exactly, never the real internal `hold_reason`).
--    `app.submit_loyalty_redemption`/`app.decide_loyalty_redemption`'s own
--    already-shipped `account_on_hold` error text (CPL-321) is untouched
--    and already generic. A CONFIRMED case's own internal `review_reason`
--    is likewise never surfaced to any customer-facing read.
-- 10. **No autonomous punitive action (business rule + alternative flow).**
--    `app.open_loyalty_fraud_review_case` applies only a PROVISIONAL hold
--    (via the SAME idempotent, reversible primitive CPL-317 already ships)
--    -- never deletes, closes, or otherwise punitively mutates the loyalty
--    account itself. `'confirm'` in `app.decide_loyalty_fraud_review_case`
--    performs NO ACTION beyond recording the decision -- the hold, already
--    applied at open time, simply stays in place; there is no cascading
--    escalation, no automatic account closure, nothing beyond exactly what
--    the human reviewer's own RPC call just decided (grep-confirmed: the
--    `p_decision = 'confirm'` branch touches no table besides `app.loyalty_
--    fraud_review_cases` itself).
-- 11. Every actor-taking function calls `app.assert_actor_is_session_
--    identity` as its own literal FIRST statement; every staff mutate/
--    get-by-id RPC checks `LYL:*` authority BEFORE fetching its target row
--    (C-05, mirrors every prior Loyalty checkpoint's own identical
--    discipline).
-- 12. **Idempotency**: `app.open_loyalty_fraud_review_case` carries a real
--    `unique(tenant_id, idempotency_key)` on `app.loyalty_fraud_review_
--    cases`, the authority check running BEFORE the idempotent short-circuit
--    SELECT (which also verifies the full target tuple -- `loyalty_
--    account_id`/`risk_signal_type` -- on a key match, C-01), a real
--    `exception when unique_violation` handler that DISTINGUISHES a genuine
--    idempotency-key race from the partial "one open/under_review case per
--    account" index conflict by re-checking the idempotency key first
--    (mirrors `app.issue_loyalty_benefit_entitlement`'s own identical
--    distinguishing shape, CPL-319), and the case row's own INSERT happens
--    strictly BEFORE composing the hold (so a losing idempotency-key racer
--    never reaches the hold-composition step at all -- the CPL-318 ordering
--    lesson, applied here even though this table has no separate aggregate
--    balance to double-count, purely for the SAME "never mutate anything
--    downstream of a failed idempotency claim" discipline).
-- 13. **Optimistic concurrency (`app.claim_loyalty_fraud_review_case`/`app.
--    decide_loyalty_fraud_review_case`/`app.revoke_loyalty_fraud_review_
--    suppression`): the NULL-bypass fix applied from the start** -- every
--    function rejects `p_expected_version is null` explicitly, BEFORE the
--    bare `<>` comparison (which alone evaluates to SQL NULL, falsy, for a
--    NULL input) could silently pass it through, AND every UPDATE repeats
--    `and record_version = p_expected_version` on the statement itself
--    (CPL-321's own "double-defended" shape, mirrored verbatim here) --
--    live regression-proven per function in this checkpoint's own db-test.
-- 14. **`clock_timestamp()`, never `now()`, throughout** -- every `created_
--    at`/`updated_at`/`decided_at`/`expires_at`-comparison/`revoked_at` in
--    this file, and both new touch-row triggers -- the CPL-315 self-found
--    defect class, applied proactively from the first draft (as every
--    Loyalty checkpoint since CPL-317 already does).
-- 15. **LYL permission mapping, reused from CPL-316..321 unchanged.**
--    Ordinary sweep/claim actions -> `LYL:Edit`. Opening/deciding a fraud
--    case and suppress/revoke (all governance-grade, decision 4/7) ->
--    `LYL:Configure`. Staff reads -> `LYL:View`. Customer-facing hold-status
--    read -> scoped via `app.resolve_customer_account_scope` only, no staff
--    RBAC check, mirroring CPL-316..321 exactly.
-- 16. **RLS: `authenticated` holds ZERO direct grant** on either new table,
--    mirroring CPL-316..321 exactly -- the RPCs below are the only
--    sanctioned access path, for staff and customer callers alike. Neither
--    table is `append_only_ledger`-family (both are genuinely mutable,
--    governed current-state rows with a real history trail via their own
--    `status`/`revoked_at` transitions, not a ledger CPL-318's own RPD-022/
--    ISS-2026-130 disclosure concerns) -- no NEW RPD-022 citation is needed.
-- 17. Per `ERR-2026-004`: this migration carries its own explicit `revoke
--    execute on all functions in schema app from public` statement before
--    its final grants.
-- 18. **Cursor pagination**: `(tenant_id, updated_at desc, id desc)` on
--    `app.list_loyalty_fraud_review_cases`/`app.list_loyalty_expiry_runs`
--    (both have a real `updated_at`); `(tenant_id, created_at desc, id
--    desc)` on `app.list_loyalty_fraud_review_suppressions` (no `updated_
--    at` column -- mirrors `app.list_loyalty_account_tier_movements`/`app.
--    list_loyalty_benefit_entitlement_events`'s own identical "no
--    updated_at -> use created_at" precedent). Never `OFFSET`.

-- ===========================================================================
-- 0. Widen app.jobs.job_type (design decision 2) -- the established drop/
-- add-constraint pattern, current full list carried forward verbatim (grep-
-- verified against every prior `drop constraint jobs_job_type_check`
-- migration, HRT-291's own the most recent) plus this checkpoint's own one
-- new value. app.generic_job_types() (ATW-031/ISS-2026-012 single source of
-- truth for app.enqueue_job/app.dispatch_event_as_job) widened identically.
-- ===========================================================================

alter table app.jobs drop constraint jobs_job_type_check;
alter table app.jobs add constraint jobs_job_type_check check (
  job_type in (
    'import', 'export', 'report_generation', 'notification_batch', 'webhook_retry', 'document_generation',
    'dashboard_refresh', 'loyalty_expiration', 'recurring_billing', 'integration_sync',
    'route_load_planning', 'print_label', 'roster_generation', 'leave_accrual', 'leave_carry_forward_expiry',
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep'
  )
);

comment on constraint jobs_job_type_check on app.jobs is
  'CPL-322 (mirrors HRT-289/291''s own identical widening pattern): widened to add ''loyalty_expiry_sweep'' -- a genuinely new literal, disclosed as NOT a reuse of the pre-existing, never-realized ''loyalty_expiration'' placeholder (design decision 2). Kept set-equal with app.generic_job_types() by the standing ATW-031 drift-gate assertion (scripts/db-tests/background-job.sql).';

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
    'payroll_calculation', 'training_certificate_expiry', 'training_certificate_expiry_reminder',
    'ticket_sla_evaluation', 'kb_article_expiry', 'ticket_escalation_evaluation', 'loyalty_expiry_sweep'
  ]::text[];
$$;

comment on function app.generic_job_types is
  'ATW-031 (ISS-2026-012), widened by CPL-322 to add ''loyalty_expiry_sweep''. Unchanged callers: app.enqueue_job and app.dispatch_event_as_job.';

-- ===========================================================================
-- 1. app.loyalty_fraud_review_cases -- one row per governed fraud review
-- case, mutable (status/reviewed_by/review_reason/decided_at), never
-- deleted (design decision 5).
-- ===========================================================================

create table app.loyalty_fraud_review_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  risk_signal_type text not null,
  risk_signal_detail text not null,
  status text not null default 'open',
  opened_by text,
  reviewed_by text,
  review_reason text,
  decided_at timestamptz,
  idempotency_key text not null,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lfrc_risk_signal_type_check check (risk_signal_type in ('velocity_anomaly', 'duplicate_device', 'manual_flag', 'other')),
  constraint lfrc_risk_signal_detail_check check (length(trim(risk_signal_detail)) > 0),
  constraint lfrc_status_check check (status in ('open', 'under_review', 'confirmed', 'cleared')),
  constraint lfrc_decision_shape_check check (
    (status in ('open', 'under_review') and reviewed_by is null and review_reason is null and decided_at is null)
    or (status in ('confirmed', 'cleared') and reviewed_by is not null and review_reason is not null and decided_at is not null)
  ),
  constraint lfrc_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_fraud_review_cases is
  'CPL-322: a governed fraud review case. risk_signal_type/risk_signal_detail are RESTRICTED INTERNAL DATA (business rule) -- read ONLY by LYL:View-gated staff RPCs, structurally absent from app.list_customer_portal_loyalty_account_hold_status (design decision 9). lfrc_single_active_per_account (below) enforces at most one OPEN/UNDER_REVIEW case per loyalty_account at a time. Opening a case composes app.hold_loyalty_account_tier_benefits (CPL-317, design decision 3) -- never a direct app.loyalty_account_tier_holds write, never a second, competing account-hold table.';

create unique index lfrc_single_active_per_account on app.loyalty_fraud_review_cases (tenant_id, loyalty_account_id) where status in ('open', 'under_review');
create index lfrc_tenant_updated_id_idx on app.loyalty_fraud_review_cases (tenant_id, updated_at desc, id desc);
create index lfrc_account_idx on app.loyalty_fraud_review_cases (loyalty_account_id);

create function app.touch_loyalty_fraud_review_case_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_fraud_review_cases_touch_row
  before update on app.loyalty_fraud_review_cases
  for each row
  execute function app.touch_loyalty_fraud_review_case_row();

-- ===========================================================================
-- 2. app.loyalty_fraud_review_suppressions -- authority/reason/expiry-gated
-- cooldown, mirrors app.ticket_escalation_suppressions' own exact shape
-- (design decision 7).
-- ===========================================================================

create table app.loyalty_fraud_review_suppressions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  reason text not null,
  expires_at timestamptz not null,
  suppressed_by_auth_user_id uuid not null,
  suppressed_by text,
  revoked_at timestamptz,
  revoked_by text,
  revoked_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  constraint lfrs_reason_check check (length(trim(reason)) > 0)
);

comment on column app.loyalty_fraud_review_suppressions.expires_at is
  'CPL-322 (mirrors app.ticket_escalation_suppressions.expires_at exactly, HRT-291): app.suppress_loyalty_fraud_review validates expires_at > clock_timestamp() at INSERT time -- deliberately not a table CHECK against created_at (which would only ever compare two values captured in the same instant).';

comment on table app.loyalty_fraud_review_suppressions is
  'CPL-322 (design decision 7, business rule "suppression/cooldown requires authority, reason, expiry, never hides compliance reporting" -- word-for-word the same language HRT-291''s own app.ticket_escalation_suppressions comment uses): LYL:Configure-gated (app.suppress_loyalty_fraud_review). At most one non-revoked row per loyalty_account_id at a time (lfrs_active_unique below); an already-expired-but-unrevoked row is auto-revoked (revoked_reason=''expired'') the next time it is checked -- inside app.open_loyalty_fraud_review_case itself, the one place a suppression''s presence ever actually matters. Never hides app.loyalty_fraud_review_cases/app.loyalty_account_tier_holds -- suppression only gates whether a NEW case may be opened.';

create unique index lfrs_active_unique on app.loyalty_fraud_review_suppressions (loyalty_account_id) where revoked_at is null;
create index lfrs_account_idx on app.loyalty_fraud_review_suppressions (loyalty_account_id, revoked_at);
create index lfrs_tenant_created_id_idx on app.loyalty_fraud_review_suppressions (tenant_id, created_at desc, id desc);

-- ===========================================================================
-- 3. app.run_loyalty_expiry_sweep / app.list_loyalty_expiry_runs -- staff/
-- system, LYL:Edit / LYL:View (design decision 1).
-- ===========================================================================

create function app.run_loyalty_expiry_sweep(
  p_tenant_id uuid,
  p_as_of timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_run_label text default null
)
returns table (
  job_id uuid,
  status text,
  run_label text,
  lots_expired_count integer,
  entitlements_expired_count integer
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
  v_run_label text;
  v_job app.jobs;
  v_worker_id text;
  v_lots_count integer := 0;
  v_entitlements_count integer := 0;
  v_final app.jobs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_run_label := coalesce(nullif(trim(p_run_label), ''), to_char(v_as_of, 'YYYY-MM-DD'));

  v_job := app.enqueue_job(
    p_tenant_id, 'loyalty_expiry_sweep', jsonb_build_object('as_of', v_as_of, 'run_label', v_run_label),
    0, 'loyalty_expiry_sweep:' || p_tenant_id::text || ':' || v_run_label, 1, p_actor_auth_user_id, p_actor_label
  );

  if v_job.status = 'pending' then
    v_worker_id := 'inline-loyalty-expiry-sweep:' || p_actor_auth_user_id::text;
    update app.jobs j set status = 'in_progress', locked_by = v_worker_id, locked_until = clock_timestamp() + interval '10 minutes'
    where j.job_id = v_job.job_id and j.status = 'pending';

    -- Composes the two already-real, already-idempotent, tenant-wide expiry
    -- primitives (CPL-318/319) -- never reimplements either's own scan/
    -- posting logic. Real counts, from each function's own actually-
    -- returned row set.
    select count(*) into v_lots_count from app.expire_loyalty_point_lots(p_tenant_id, p_actor_auth_user_id, p_actor_label);
    select count(*) into v_entitlements_count from app.expire_loyalty_benefit_entitlements(p_tenant_id, p_actor_auth_user_id, p_actor_label);

    -- Design decision 1: real counts recorded ON THE COMPLETED JOB ROW
    -- itself, via the job's own already-jsonb, already-not-null payload
    -- column, extended additively. Table-aliased (`j`) -- this function's
    -- own RETURNS TABLE clause implicitly declares job_id/status as
    -- PL/pgSQL variables in scope, the exact CPL-317-style ambiguous-column
    -- defect class, live-caught during this checkpoint's own smoke test
    -- before this file was finalized.
    update app.jobs j
    set payload = j.payload || jsonb_build_object('lots_expired_count', v_lots_count, 'entitlements_expired_count', v_entitlements_count)
    where j.job_id = v_job.job_id;

    v_final := app.complete_job(v_job.job_id, v_worker_id, null, p_actor_label);

    perform app.capture_audit_event(
      p_tenant_id, p_actor_auth_user_id, p_actor_label, 'run_loyalty_expiry_sweep',
      'app.jobs', v_job.job_id, 'success', null, null,
      jsonb_build_object('run_label', v_run_label, 'lots_expired_count', v_lots_count, 'entitlements_expired_count', v_entitlements_count)
    );
  else
    -- A replay of an already-processed (or already in-flight, per decision
    -- 1's own live-proven serialize-then-no-op race outcome) period -- a
    -- safe no-op, returning whatever the ORIGINAL run's own payload holds.
    v_final := v_job;
    v_lots_count := coalesce((v_final.payload->>'lots_expired_count')::integer, 0);
    v_entitlements_count := coalesce((v_final.payload->>'entitlements_expired_count')::integer, 0);
  end if;

  job_id := v_final.job_id;
  status := v_final.status;
  run_label := v_run_label;
  lots_expired_count := v_lots_count;
  entitlements_expired_count := v_entitlements_count;
  return next;
end;
$$;

comment on function app.run_loyalty_expiry_sweep is
  'CPL-322 (design decision 1, mirrors app.run_ticket_escalation_evaluation_batch/app.run_ticket_sla_evaluation_batch exactly): a real app.jobs row tracked through the actual PLT-132 lifecycle. Idempotent per (tenant, run_label) at the JOB level -- a genuinely concurrent overlapping call for the SAME tenant+run_label SERIALIZES on app.enqueue_job''s own real unique-constraint blocking behavior, then correctly no-ops once it sees the row already completed, live-proven with a real two-process race in this checkpoint''s own db-test. No live scheduler exists anywhere in this repository (the same disclosed NOT_RUN class PLT-123/125/132/HRT-289/291) -- this is the real, callable, tested entry point a future scheduler would invoke periodically.';

create function app.list_loyalty_expiry_runs(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  job_id uuid,
  status text,
  run_label text,
  as_of timestamptz,
  lots_expired_count integer,
  entitlements_expired_count integer,
  error text,
  created_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    j.job_id, j.status, (j.payload->>'run_label'), (j.payload->>'as_of')::timestamptz,
    coalesce((j.payload->>'lots_expired_count')::integer, 0), coalesce((j.payload->>'entitlements_expired_count')::integer, 0),
    j.error, j.created_at, j.completed_at, j.updated_at
  from app.jobs j
  where j.tenant_id = p_tenant_id and j.job_type = 'loyalty_expiry_sweep'
    and (p_cursor_id is null or (j.updated_at, j.job_id) < (p_cursor_updated_at, p_cursor_id))
  order by j.updated_at desc, j.job_id desc
  limit v_limit;
end;
$$;

comment on function app.list_loyalty_expiry_runs is
  'CPL-322: staff preview/review of expiry sweep run history -- reads app.jobs rows this checkpoint''s own app.run_loyalty_expiry_sweep creates, decoding the real counts/run_label/as_of it stamps into payload.';

-- ===========================================================================
-- 4. app.open_loyalty_fraud_review_case -- staff, LYL:Configure (design
-- decision 4). Opens a case AND composes a provisional account hold.
-- ===========================================================================

create function app.open_loyalty_fraud_review_case(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_risk_signal_type text,
  p_risk_signal_detail text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_fraud_review_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_existing app.loyalty_fraud_review_cases;
  v_account app.loyalty_accounts;
  v_suppression app.loyalty_fraud_review_suppressions;
  v_case app.loyalty_fraud_review_cases;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant % -- opening a fraud review case immediately applies a provisional account hold, the same elevated authority app.hold_loyalty_account_tier_benefits itself requires (design decision 4)', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_risk_signal_type is null or p_risk_signal_type not in ('velocity_anomaly', 'duplicate_device', 'manual_flag', 'other') then
    raise exception 'invalid_risk_signal_type: % is not one of velocity_anomaly/duplicate_device/manual_flag/other', p_risk_signal_type using errcode = 'check_violation';
  end if;
  if p_risk_signal_detail is null or length(trim(p_risk_signal_detail)) = 0 then
    raise exception 'risk_signal_detail_required: a non-empty internal risk signal detail is required' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required' using errcode = 'check_violation';
  end if;

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern),
  -- verifying the full target tuple on a key match (C-01).
  select * into v_existing from app.loyalty_fraud_review_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.loyalty_account_id <> p_loyalty_account_id or v_existing.risk_signal_type <> p_risk_signal_type then
      raise exception 'idempotency_key_conflict: idempotency key % was already used for a different fraud review case', p_idempotency_key using errcode = 'unique_violation';
    end if;
    return v_existing;
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  -- Suppression gate (design decision 7, mirrors app._evaluate_ticket_
  -- escalation's own auto-revoke-on-check pattern, HRT-291): an active,
  -- unexpired suppression blocks a NEW case; a stale, unrevoked, already-
  -- expired one is auto-revoked here, the first time it is checked.
  select * into v_suppression from app.loyalty_fraud_review_suppressions where loyalty_account_id = p_loyalty_account_id and revoked_at is null for update;
  if v_suppression.id is not null then
    if v_suppression.expires_at > clock_timestamp() then
      raise exception 'fraud_review_suppressed: an active suppression prevents opening a new review case for loyalty account % until %', p_loyalty_account_id, v_suppression.expires_at using errcode = 'check_violation';
    end if;
    update app.loyalty_fraud_review_suppressions set revoked_at = clock_timestamp(), revoked_by = 'system:fraud-review-case-open', revoked_reason = 'expired'
    where id = v_suppression.id;
  end if;

  -- The case row's own INSERT (the idempotency claim, and the partial-
  -- unique-index guard) happens strictly BEFORE composing the hold (design
  -- decision 12) -- a losing idempotency-key racer never reaches the hold
  -- composition step at all.
  begin
    insert into app.loyalty_fraud_review_cases (tenant_id, loyalty_account_id, risk_signal_type, risk_signal_detail, opened_by, idempotency_key)
    values (p_tenant_id, p_loyalty_account_id, p_risk_signal_type, trim(p_risk_signal_detail), p_actor_label, p_idempotency_key)
    returning * into v_case;
  exception
    when unique_violation then
      -- Could be a genuine idempotency-key race (another caller already
      -- won) OR the partial "one open/under_review case per account" index
      -- -- distinguish by re-checking the idempotency key first (mirrors
      -- app.issue_loyalty_benefit_entitlement's own identical distinguishing
      -- shape, CPL-319).
      select * into v_existing from app.loyalty_fraud_review_cases where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if found then
        return v_existing;
      end if;
      raise exception 'fraud_review_case_already_active: loyalty account % already has an open or under_review fraud review case', p_loyalty_account_id using errcode = 'check_violation';
  end;

  -- Composes app.hold_loyalty_account_tier_benefits (CPL-317) -- never a
  -- direct app.loyalty_account_tier_holds write (design decision 3).
  -- Idempotent by construction on the composed side too: an already-held
  -- account (from a prior case or a direct staff hold) is a safe no-op
  -- preserving the ORIGINAL hold_reason.
  perform app.hold_loyalty_account_tier_benefits(
    p_tenant_id, p_loyalty_account_id,
    'Fraud review case ' || v_case.id::text || ' opened (' || p_risk_signal_type || '): ' || trim(p_risk_signal_detail),
    p_actor_auth_user_id, p_actor_label
  );

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'open_loyalty_fraud_review_case',
    'app.loyalty_fraud_review_cases', v_case.id, 'success', null, null,
    jsonb_build_object('loyalty_account_id', p_loyalty_account_id, 'risk_signal_type', p_risk_signal_type)
  );

  return v_case;
end;
$$;

comment on function app.open_loyalty_fraud_review_case is
  'CPL-322: idempotent on (tenant_id, idempotency_key), verifying the full target tuple on a key match. At most one OPEN/UNDER_REVIEW case per loyalty_account at a time (lfrc_single_active_per_account). Composes app.hold_loyalty_account_tier_benefits (design decision 3) -- the SAME account-level hold app.submit_loyalty_redemption (CPL-321) already reads directly.';

-- ===========================================================================
-- 5. app.claim_loyalty_fraud_review_case -- staff, LYL:Edit. Disclosed 3rd
-- function (design decision 6). open -> under_review.
-- ===========================================================================

create function app.claim_loyalty_fraud_review_case(
  p_tenant_id uuid,
  p_case_id uuid,
  p_expected_version integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_fraud_review_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.loyalty_fraud_review_cases;
  v_updated app.loyalty_fraud_review_cases;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_case from app.loyalty_fraud_review_cases c where c.id = p_case_id and c.tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_fraud_review_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  if p_expected_version is null or v_case.record_version <> p_expected_version then
    raise exception 'stale_version: fraud review case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_case.status <> 'open' then
    raise exception 'invalid_transition: fraud review case % is % -- only an open case may be claimed for review', p_case_id, v_case.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_fraud_review_cases
  set status = 'under_review'
  -- NULL-bypass fix (design decision 13): the predicate is repeated here.
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: fraud review case % was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'claim_loyalty_fraud_review_case',
    'app.loyalty_fraud_review_cases', v_updated.id, 'success', null, jsonb_build_object('status', 'open'), jsonb_build_object('status', 'under_review')
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 6. app.decide_loyalty_fraud_review_case -- staff, LYL:Configure
-- (governance-grade). confirm keeps the hold; clear releases it (design
-- decisions 4/10).
-- ===========================================================================

create function app.decide_loyalty_fraud_review_case(
  p_tenant_id uuid,
  p_case_id uuid,
  p_expected_version integer,
  p_decision text,
  p_review_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_fraud_review_cases
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.loyalty_fraud_review_cases;
  v_updated app.loyalty_fraud_review_cases;
  v_new_status text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_decision is null or p_decision not in ('confirm', 'clear') then
    raise exception 'invalid_decision: % is not one of confirm/clear', p_decision using errcode = 'check_violation';
  end if;
  if p_review_reason is null or length(trim(p_review_reason)) = 0 then
    raise exception 'reason_required: a non-empty review reason is required to decide a fraud review case' using errcode = 'not_null_violation';
  end if;

  select * into v_case from app.loyalty_fraud_review_cases c where c.id = p_case_id and c.tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_fraud_review_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;
  -- NULL-bypass double-defense (design decision 13, mirrors app.decide_
  -- loyalty_redemption exactly): an explicit up-front check, not only the
  -- UPDATE's own repeated predicate.
  if p_expected_version is null or v_case.record_version <> p_expected_version then
    raise exception 'stale_version: fraud review case % expected version % but found %', p_case_id, p_expected_version, v_case.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_case.status not in ('open', 'under_review') then
    raise exception 'invalid_transition: fraud review case % is % and cannot be decided', p_case_id, v_case.status
      using errcode = 'check_violation';
  end if;

  v_new_status := case when p_decision = 'confirm' then 'confirmed' else 'cleared' end;

  update app.loyalty_fraud_review_cases
  set status = v_new_status, reviewed_by = p_actor_label, review_reason = p_review_reason, decided_at = clock_timestamp()
  -- NULL-bypass fix: the predicate is repeated on the UPDATE itself.
  where id = p_case_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: fraud review case % was concurrently modified (expected version %)', p_case_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  -- Design decision 10 (no autonomous punitive action): 'clear' composes
  -- app.release_loyalty_account_tier_benefits (never a direct table write).
  -- 'confirm' performs NO further action -- the hold, already applied at
  -- open time, simply stays in place; nothing beyond exactly what this
  -- human reviewer's own call just decided.
  if p_decision = 'clear' then
    perform app.release_loyalty_account_tier_benefits(p_tenant_id, v_case.loyalty_account_id, p_actor_auth_user_id, p_actor_label);
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'decide_loyalty_fraud_review_case',
    'app.loyalty_fraud_review_cases', v_updated.id, 'success', p_review_reason,
    jsonb_build_object('status', v_case.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.decide_loyalty_fraud_review_case is
  'CPL-322: staff-only, LYL:Configure. Mandatory non-empty review_reason. clear composes app.release_loyalty_account_tier_benefits (CPL-317) -- releases whatever hold is currently active on the account, regardless of whether it originated from THIS case or a separate staff action (disclosed limitation, consistent with CPL-317''s own single-hold-row-per-account model). confirm keeps the hold in place with no further autonomous action (design decision 10).';

-- ===========================================================================
-- 7. app.suppress_loyalty_fraud_review / app.revoke_loyalty_fraud_review_
-- suppression -- staff, LYL:Configure (design decision 7).
-- ===========================================================================

create function app.suppress_loyalty_fraud_review(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_reason text,
  p_expires_at timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_fraud_review_suppressions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_stale app.loyalty_fraud_review_suppressions;
  v_active app.loyalty_fraud_review_suppressions;
  v_row app.loyalty_fraud_review_suppressions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant % -- suppression requires the elevated Loyalty governance authority', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a reason is required to suppress fraud review for this account' using errcode = 'check_violation';
  end if;
  if p_expires_at is null or p_expires_at <= clock_timestamp() then
    raise exception 'invalid_expiry: p_expires_at must be a real, future timestamp' using errcode = 'check_violation';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  select * into v_stale from app.loyalty_fraud_review_suppressions where loyalty_account_id = p_loyalty_account_id and revoked_at is null for update;
  if v_stale.id is not null then
    if v_stale.expires_at > clock_timestamp() then
      raise exception 'fraud_review_already_suppressed: an active suppression already covers loyalty account % until % -- revoke it first', p_loyalty_account_id, v_stale.expires_at using errcode = 'check_violation';
    end if;
    update app.loyalty_fraud_review_suppressions set revoked_at = clock_timestamp(), revoked_by = p_actor_label, revoked_reason = 'expired'
    where id = v_stale.id;
  end if;

  begin
    insert into app.loyalty_fraud_review_suppressions (tenant_id, loyalty_account_id, reason, expires_at, suppressed_by_auth_user_id, suppressed_by)
    values (p_tenant_id, p_loyalty_account_id, p_reason, p_expires_at, p_actor_auth_user_id, p_actor_label)
    returning * into v_row;
  exception
    when unique_violation then
      select * into v_active from app.loyalty_fraud_review_suppressions where loyalty_account_id = p_loyalty_account_id and revoked_at is null;
      if v_active.id is null then
        raise;
      end if;
      raise exception 'fraud_review_already_suppressed: a concurrent suppression was just created for loyalty account %', p_loyalty_account_id using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'suppress_loyalty_fraud_review',
    'app.loyalty_fraud_review_suppressions', v_row.id, 'success', p_reason, null,
    jsonb_build_object('loyalty_account_id', p_loyalty_account_id, 'expires_at', v_row.expires_at)
  );

  return v_row;
end;
$$;

comment on function app.suppress_loyalty_fraud_review is
  'CPL-322 (mirrors app.suppress_ticket_escalation exactly, HRT-291 decision 11): at most one non-revoked row per loyalty_account_id at a time; a stale, unrevoked, already-expired row is auto-revoked here before a new one is inserted.';

create function app.revoke_loyalty_fraud_review_suppression(
  p_tenant_id uuid,
  p_suppression_id uuid,
  p_expected_version integer,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_fraud_review_suppressions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_row app.loyalty_fraud_review_suppressions;
  v_updated app.loyalty_fraud_review_suppressions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app.loyalty_fraud_review_suppressions s where s.id = p_suppression_id and s.tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_fraud_review_suppression_not_found: %', p_suppression_id using errcode = 'no_data_found';
  end if;
  -- NULL-bypass fix (design decision 13).
  if p_expected_version is null or v_row.record_version <> p_expected_version then
    raise exception 'stale_version: suppression % expected version % but found %', p_suppression_id, p_expected_version, v_row.record_version
      using errcode = 'serialization_failure';
  end if;
  if v_row.revoked_at is not null then
    return v_row;
  end if;

  update app.loyalty_fraud_review_suppressions
  set revoked_at = clock_timestamp(), revoked_by = p_actor_label, revoked_reason = coalesce(nullif(trim(p_reason), ''), 'revoked by staff'), record_version = record_version + 1
  -- NULL-bypass fix: the predicate is repeated on the UPDATE itself.
  where id = p_suppression_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: suppression % was concurrently modified (expected version %)', p_suppression_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'revoke_loyalty_fraud_review_suppression',
    'app.loyalty_fraud_review_suppressions', v_updated.id, 'success', p_reason, null,
    jsonb_build_object('loyalty_account_id', v_updated.loyalty_account_id)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 8. Staff reads -- LYL:View.
-- ===========================================================================

create function app.get_loyalty_fraud_review_case(p_tenant_id uuid, p_case_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_fraud_review_cases
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_case app.loyalty_fraud_review_cases;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_case from app.loyalty_fraud_review_cases where id = p_case_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_fraud_review_case_not_found: %', p_case_id using errcode = 'no_data_found';
  end if;

  return v_case;
end;
$$;

create function app.list_loyalty_fraud_review_cases(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_fraud_review_cases
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select c.* from app.loyalty_fraud_review_cases c
  where c.tenant_id = p_tenant_id
    and (p_loyalty_account_id is null or c.loyalty_account_id = p_loyalty_account_id)
    and (p_status is null or c.status = p_status)
    and (p_cursor_id is null or (c.updated_at, c.id) < (p_cursor_updated_at, p_cursor_id))
  order by c.updated_at desc, c.id desc
  limit v_limit;
end;
$$;

create function app.list_loyalty_fraud_review_suppressions(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_active_only boolean default false,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_fraud_review_suppressions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_cursor_id is not null and p_cursor_created_at is null then
    raise exception 'invalid_cursor: p_cursor_created_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select s.* from app.loyalty_fraud_review_suppressions s
  where s.tenant_id = p_tenant_id
    and (p_loyalty_account_id is null or s.loyalty_account_id = p_loyalty_account_id)
    and (not p_active_only or s.revoked_at is null)
    and (p_cursor_id is null or (s.created_at, s.id) < (p_cursor_created_at, p_cursor_id))
  order by s.created_at desc, s.id desc
  limit v_limit;
end;
$$;

comment on function app.list_loyalty_fraud_review_suppressions is
  'CPL-322: keyset-paginated on (created_at desc, id desc) -- app.loyalty_fraud_review_suppressions has no updated_at column (design decision 18).';

-- ===========================================================================
-- 9. app.list_customer_portal_loyalty_account_hold_status -- customer-facing
-- (Layer 4, ADR-0024 Part A). Deny-by-default. Generic notice only, never
-- risk_signal_type/risk_signal_detail/review_reason/reviewed_by (design
-- decision 9).
-- ===========================================================================

create function app.list_customer_portal_loyalty_account_hold_status(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_account_id uuid default null,
  p_limit integer default 50
)
returns table (
  loyalty_account_id uuid,
  program_name text,
  is_on_hold boolean,
  hold_notice text
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_scope uuid[];
  v_limit integer;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_customer_account_id is not null and not (p_customer_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select
    la.id,
    p.name,
    coalesce(h.is_held, false),
    case when coalesce(h.is_held, false) then 'Your loyalty account is temporarily on hold. Contact your account administrator or support for details.' else null end
  from app.loyalty_accounts la
  join app.loyalty_programs p on p.id = la.program_id
  left join app.loyalty_account_tier_holds h on h.tenant_id = p_tenant_id and h.loyalty_account_id = la.id
  where la.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and la.status = 'active'
    and (p_customer_account_id is null or la.customer_account_id = p_customer_account_id)
  order by la.updated_at desc, la.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_account_hold_status is
  'CPL-322: a lightweight, reusable, customer-safe hold-status projection -- reads ONLY app.loyalty_account_tier_holds.is_held (the SAME table app.open_loyalty_fraud_review_case composes a hold onto), never app.loyalty_fraud_review_cases at all (structurally, grep-provably impossible to leak risk_signal_type/risk_signal_detail/review_reason/reviewed_by through this function, design decision 9). Deny-by-default: an out-of-scope p_customer_account_id or an empty resolved scope both return zero rows, never an error.';

-- ===========================================================================
-- 10. RLS -- enable, grant service_role only (design decision 16).
-- ===========================================================================

alter table app.loyalty_fraud_review_cases enable row level security;
alter table app.loyalty_fraud_review_suppressions enable row level security;

grant select, insert, update on app.loyalty_fraud_review_cases to service_role;
grant select, insert, update on app.loyalty_fraud_review_suppressions to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.run_loyalty_expiry_sweep(uuid, timestamptz, uuid, text, text) to authenticated, service_role;
grant execute on function app.list_loyalty_expiry_runs(uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.open_loyalty_fraud_review_case(uuid, uuid, text, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.claim_loyalty_fraud_review_case(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.decide_loyalty_fraud_review_case(uuid, uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.suppress_loyalty_fraud_review(uuid, uuid, text, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.revoke_loyalty_fraud_review_suppression(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_fraud_review_case(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_fraud_review_cases(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_loyalty_fraud_review_suppressions(uuid, uuid, uuid, boolean, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_account_hold_status(uuid, uuid, uuid, integer) to authenticated, service_role;
