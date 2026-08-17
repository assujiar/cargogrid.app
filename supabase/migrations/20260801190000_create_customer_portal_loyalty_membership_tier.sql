-- Phase 8 capability CPL-317 (CG-S13-CPL-019, Prompt 317, "Membership Tier").
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md
-- Part D, supabase/migrations/20260730190000_create_advanced_tms_inventory_
-- ledger.sql, docs/build-log/phase-08/CPL-316.md, and supabase/migrations/
-- 20260801180000_create_customer_portal_loyalty_program_earning.sql IN FULL
-- before writing any of this file. This migration READS app.loyalty_accounts/
-- app.loyalty_earning_events (CPL-316) -- it never INSERTs/UPDATEs/DELETEs
-- against either table, confirmed by grep before this file was finalized.
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **tier_rank convention: higher tier_rank = a more prestigious/higher
--    tier** (my own call, disclosed, per this prompt's own "ordering,
--    lower/higher = your call, disclose it"). Bronze=1, Silver=2, Gold=3, etc.
-- 2. **Versioning granularity: one draft/published/superseded lineage PER
--    (program_id, tier_name)**, not one lineage per whole program (a
--    "publish the whole schema atomically" shape was considered and
--    rejected -- it would require a second parent "tier schema version"
--    table this prompt's own literal column list does not name, and CPL-316's
--    own precedent already versions independently at the finest natural
--    grain, e.g. one rule version per program, never bundling unrelated
--    config together). Each row IS one version, mirroring CPL-316's own
--    loyalty_program_rule_versions collapse (program+rule+version onto one
--    row, no separate parent "rule" identity table) applied here one level
--    finer (per tier_name within a program). `unique(program_id, tier_name,
--    version_number)`; at most one draft and one published row per
--    (program_id, tier_name) at a time (partial unique indexes below) --
--    "a tier definition change publishes a NEW version, never mutates a
--    published one" (business rule) holds per-tier-name, exactly as CPL-316's
--    own rule versions hold per-program.
-- 3. **`to_tier_id` and `tier_definition_version_id` are two distinctly named
--    columns per this prompt's own literal schema, but always carry the
--    IDENTICAL value in this checkpoint's own flattened tier-identity/version
--    design** (design decision 2: one row already IS one version, there is
--    no separate parent "tier identity" row `to_tier_id` could point to that
--    `tier_definition_version_id` would need to differ from). Both are kept
--    as distinct, independently-named columns -- not collapsed into one --
--    so a future capability that ever splits "tier identity" from "tier
--    version" (the way `app.loyalty_programs`/`app.loyalty_program_rule_
--    versions` already split at the PROGRAM level) can widen
--    `tier_definition_version_id`'s own meaning additively, without a
--    breaking rename of `to_tier_id`. Disclosed as `ISS-2026-127` item 3,
--    not a silent redundancy.
-- 4. **A real, explicit, working downgrade-timing policy (source prompt's own
--    Alternative flow: "Downgrade occurs at review period end... according
--    to configured policy"), not an ambiguous one.** `app.loyalty_tier_
--    definitions.review_period_days integer not null default 0` (a genuine
--    addition beyond this prompt's own literal column list, required to make
--    the policy real rather than aspirational -- disclosed, mirrors CPL-316's
--    own `eligibility_config` jsonb precedent of a config field a business
--    rule requires but the literal column list under-specifies). Every
--    `app.loyalty_account_tier_movements` row stamps its own `next_review_at`
--    (`created_at + review_period_days` of the tier it moves the account
--    INTO) at insertion time -- self-contained and immutable once written,
--    never recomputed from the tier definition's CURRENT `review_period_days`
--    on a later call (which could retroactively change an already-recorded
--    movement's own grace window if the tier definition were ever edited --
--    it cannot be, once published, but the self-contained stamp is
--    structurally safer regardless). Policy: an UPGRADE (eligible tier
--    outranks the current one) applies IMMEDIATELY, every recalculation
--    call. A DOWNGRADE candidate (eligible tier is ranked below the current
--    one) is gated: `app.recalculate_customer_loyalty_tier` compares
--    `now()` against the CURRENT movement's own stamped `next_review_at`
--    (the grace period the account earned by entering its current tier) --
--    before that moment, the call is a safe no-op (the account keeps its
--    current tier); at or after that moment, the downgrade is applied to
--    whatever tier is CURRENTLY eligible (not a stepwise walk down one rank
--    at a time). `review_period_days = 0` (the column default) means no
--    grace period -- a downgrade applies on the very next recalculation
--    call once eligibility drops, which is what a program with no
--    configured review policy gets by default.
-- 5. **Tier tracking and benefit-hold are deliberately ORTHOGONAL.**
--    Recalculation runs (and posts upgrade/downgrade movements) regardless
--    of whether the account's benefits are currently held -- a fraud
--    investigation freezes REDEMPTION of benefits, not the underlying
--    earning-based standing computation. Disclosed, not an oversight.
-- 6. **Fraud hold: option (a) from this prompt's own two named precedents --
--    an orthogonal `is_held`/`hold_reason`/`held_by`/`held_at`/`released_by`/
--    `released_at` column set, on a NEW table this migration owns
--    (`app.loyalty_account_tier_holds`), never altering CPL-316's already-
--    applied `app.loyalty_accounts`.** A THIRD shape -- an inline
--    `is_fraud_hold_suspended` boolean directly on `app.loyalty_account_tier_
--    movements` (which this prompt's own literal column list also
--    mentions as a parenthetical option) -- was considered and REJECTED:
--    movements are APPEND-ONLY (business rule, mirrors `app.loyalty_earning_
--    events`), but a hold's own `is_held` state is inherently CURRENT/mutable
--    (asserted now, released later) -- an inline column would require
--    mutating a past, already-posted movement row's own hold flag every time
--    a hold is asserted or released, directly violating "never mutate a
--    published/posted row." A separate, genuinely mutable one-row-per-account
--    table (option (a)) has no such conflict. One row per `loyalty_account_id`
--    (`unique(tenant_id, loyalty_account_id)`), created lazily on first hold
--    (never pre-created at enrollment -- CPL-316's own enrollment RPC is
--    untouched). A held account's benefits are suppressed (empty `{}`) and
--    replaced with a customer-safe generic message (never the real internal
--    `hold_reason`, which may contain fraud-investigation detail) in
--    `app.list_customer_portal_loyalty_tier_cards`' own projection -- proven
--    live in this checkpoint's own db-test, not merely asserted.
-- 7. **`threshold_dimension` is free `text` at the schema level (matches this
--    prompt's own literal type exactly: "text (e.g. 'earning_amount_ytd')"),
--    but `app.recalculate_customer_loyalty_tier` only IMPLEMENTS computation
--    for the one named dimension, `'earning_amount_ytd'`** -- mirrors CPL-
--    316's own identical `earning_basis`/`unsupported_earning_basis` shape
--    exactly. `'earning_amount_ytd'` sums `app.loyalty_earning_events.amount`
--    (originals positive, reversals already negative -- nets out correctly
--    with no special-casing) for the account from `date_trunc('year', now())`
--    forward. Any OTHER value present on a currently-published tier
--    definition of the account's own program raises a clear
--    `unsupported_threshold_dimension` BEFORE any eligible-tier resolution
--    is attempted (never silently excluded from consideration, which would
--    misreport `no_eligible_tier_definition` instead of the real cause).
-- 8. **Eligible tier resolution**: the highest-`tier_rank` currently
--    PUBLISHED tier definition of the account's own program whose
--    `threshold_value <= computed amount` (inclusive boundary -- exactly AT
--    a threshold qualifies, this checkpoint's own db-test proves both the
--    exactly-at and one-unit-below edges). A program's own published tier
--    set is expected to include a `threshold_value = 0` base tier so every
--    enrolled account resolves to SOME tier; if none qualifies at all, a
--    real `no_eligible_tier_definition` error is raised rather than
--    silently applying nothing (disclosed as `ISS-2026-127` item 2 -- no
--    fallback/default tier is auto-created by this migration itself, tenant
--    configuration is expected to include a base rung).
-- 9. **A second partial unique index, `ltd_single_published_rank`, prevents
--    two DIFFERENT tier_name lineages of the same program from both holding
--    the same `tier_rank` while published at once** -- ambiguous "next
--    tier"/eligible-tier resolution would otherwise be possible. A genuine
--    hardening beyond the prompt's own literal ask, disclosed.
-- 10. **Idempotent recalculation is BEHAVIORAL, not idempotency-key-based** --
--    unlike `app.evaluate_customer_loyalty_earning_for_paid_invoice`
--    (keyed on a real external source event, `ar_open_item_id`), a
--    recalculation call has no natural external event key -- "recompute
--    now" is inherently a query against current derived state. Idempotency
--    is achieved by construction: when the eligible tier equals the
--    account's own current (latest-movement) tier, the call is a genuine
--    no-op, returning the existing latest movement row, never inserting a
--    new one. Concurrency-safety is a real, live mechanism, not merely
--    documented: `pg_advisory_xact_lock(hashtextextended(p_loyalty_account_
--    id::text, 3))` (salt `3`, this migration's own dedicated lock domain,
--    mirroring `20260730320000_create_advanced_tms_shipment_tracking_health_
--    writer.sql`'s own established `hashtextextended(id::text, salt)`
--    per-entity advisory-lock precedent exactly) serializes concurrent
--    recalculation calls for the SAME account within the transaction,
--    preventing two racing calls from both observing the same stale "current
--    tier" and both inserting a movement.
-- 11. **`app.loyalty_account_tier_movements.created_at` defaults to
--    `clock_timestamp()`, not `now()`** -- this table's own ordering
--    ("latest movement per account" resolves current tier) is exactly the
--    self-found CPL-315 defect class (`docs/build-log/phase-08/CPL-315.md`
--    §11.1): a test fixture recording two movements for the same account
--    inside one `do $$ ... end $$` block would otherwise tie on a frozen
--    `now()`, making "most recent" non-deterministic. Applied PROACTIVELY
--    here, not discovered by a failing run. The SAME reasoning is applied to
--    every OTHER "record when this happened" timestamp this migration
--    stamps (`loyalty_tier_definitions.created_at`/`updated_at` including
--    its own touch-trigger, `loyalty_account_tier_holds.created_at`/
--    `updated_at` including its own touch-trigger, and every explicit
--    `held_at`/`released_at`/`published_at` assignment) -- `clock_
--    timestamp()` throughout, uniformly, not only where a defect was proven.
--    The deliberate exceptions (corrected at this batch's own Tier C review
--    -- the original text here undercounted them as "the ONE"): `date_trunc
--    ('year', now())`, the YTD window boundary used identically both inside
--    `app.recalculate_customer_loyalty_tier` and the customer-facing tier-
--    card projection's own window_sum CTE; the evaluation_snapshot's own
--    `window_end := now()` value; and the downgrade grace-period gate's own
--    `now() < v_current_movement.next_review_at` comparison. All three are
--    single-transaction-consistent snapshot reads or boundary comparisons,
--    the semantically CORRECT choice in each case (a self-consistent "as
--    of" evaluation / a one-shot threshold check, never a "most recent
--    among several rows written in the same transaction" ordering decision)
--    -- not the bug class `clock_timestamp()` exists to fix.
-- 12. **Every actor-taking function calls `app.assert_actor_is_session_
--    identity` as its own literal FIRST statement**, and every staff
--    mutate/get-by-id RPC checks `LYL:*` authority BEFORE fetching its
--    target row (mirrors CPL-316's own design decision 3 exactly -- every
--    signature here already carries `p_tenant_id`, so there is no structural
--    reason to fetch first; C-05: never reveal a row's real existence/tenant
--    via a distinguishable error before authority is established).
-- 13. **LYL permission mapping, reused from CPL-316 unchanged** (this is
--    still the Loyalty domain -- `LYL:View`/`Create`/`Edit`/`Configure`,
--    no distinct module). Tier definition draft CRUD -> `Create`/`Edit`;
--    PUBLISHING a tier definition (locks it forever, changes what a future
--    recalculation resolves to) and asserting/releasing a fraud hold (a
--    governed benefit-suspension action) both map to the elevated `LYL:
--    Configure`, mirroring CPL-316's own `publish_loyalty_program_rule_
--    version`/`reverse_loyalty_earning_event` precedent exactly. Ordinary
--    recalculation posting maps to `LYL:Edit`, mirroring CPL-316's own
--    `evaluate_customer_loyalty_earning_for_paid_invoice` mapping.
-- 14. **On-demand/staff-triggered recalculation only -- NO automatic job or
--    trigger wiring in this checkpoint, disclosed plainly (not a silent
--    gap), mirroring CPL-316's own identical, already-accepted `ISS-2026-
--    126` precedent for earning evaluation.** `app.recalculate_customer_
--    loyalty_tier` is a real, complete, idempotent, fully-working RPC; the
--    scheduling mechanism (a periodic job re-running it per account) is
--    deferred, registered as `ISS-2026-127`.
-- 15. **Never mutate a derived/ledger row outside its own owning function,
--    never delete/rewrite a posted `app.loyalty_account_tier_movements`
--    row.** No `UPDATE`/`DELETE` grant on that table to `authenticated`; no
--    function in this migration ever issues `UPDATE`/`DELETE` against it. A
--    tier correction is always a NEW, linked (by `from_tier_id`) row.
-- 16. **RLS: `authenticated` holds ZERO direct grant** on any of the 3 new
--    tables, mirroring CPL-316 exactly -- the RPCs below are the only
--    sanctioned access path, for both staff and customer callers.
-- 17. **Zero reads or writes against `app.loyalty_accounts`/`app.loyalty_
--    earning_events` beyond plain `SELECT`** -- grep-confirmed before this
--    file was finalized: zero `insert into app.loyalty_accounts`/`update
--    app.loyalty_accounts`/`insert into app.loyalty_earning_events`/`update
--    app.loyalty_earning_events`/`delete from app.loyalty_accounts`/`delete
--    from app.loyalty_earning_events` anywhere in this file.
-- 18. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--    carries its own explicit `revoke execute on all functions in schema app
--    from public` statement before its final grants.

-- ===========================================================================
-- 1. app.loyalty_tier_definitions -- draft -> published -> superseded, PER
-- (program_id, tier_name) lineage (design decision 2).
-- ===========================================================================

create table app.loyalty_tier_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  program_id uuid not null references app.loyalty_programs (id),
  tier_name text not null,
  tier_rank integer not null,
  threshold_dimension text not null,
  threshold_value numeric not null,
  benefits jsonb not null default '{}'::jsonb,
  review_period_days integer not null default 0,
  version_number integer not null,
  status text not null default 'draft',
  effective_from timestamptz,
  effective_to timestamptz,
  published_by text,
  published_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint ltd_status_check check (status in ('draft', 'published', 'superseded')),
  constraint ltd_tier_name_check check (length(trim(tier_name)) > 0),
  constraint ltd_tier_rank_check check (tier_rank > 0),
  constraint ltd_threshold_dimension_check check (length(trim(threshold_dimension)) > 0),
  constraint ltd_threshold_value_check check (threshold_value >= 0),
  constraint ltd_review_period_days_check check (review_period_days >= 0),
  constraint ltd_benefits_check check (jsonb_typeof(benefits) = 'object'),
  constraint ltd_published_shape_check check (
    (status = 'draft' and published_by is null and published_at is null and effective_from is null)
    or (status in ('published', 'superseded') and published_by is not null and published_at is not null and effective_from is not null)
  ),
  constraint ltd_superseded_shape_check check ((status = 'superseded') = (effective_to is not null)),
  constraint ltd_program_tier_name_version_unique unique (program_id, tier_name, version_number)
);

comment on table app.loyalty_tier_definitions is
  'CPL-317: NEVER mutate a published version in place -- a tier definition change publishes a NEW version (app.publish_loyalty_tier_definition); historical app.loyalty_account_tier_movements retain the to_tier_id/tier_definition_version_id they were evaluated under forever. At most one draft and at most one published version per (program_id, tier_name) at a time (partial unique indexes below); at most one PUBLISHED tier per (program_id, tier_rank) at a time (design decision 9, prevents rank ambiguity across different tier_name lineages).';

create index ltd_program_idx on app.loyalty_tier_definitions (program_id);
create index ltd_tenant_updated_id_idx on app.loyalty_tier_definitions (tenant_id, updated_at desc, id desc);
create unique index ltd_single_draft_per_tier on app.loyalty_tier_definitions (program_id, tier_name) where status = 'draft';
create unique index ltd_single_published_per_tier on app.loyalty_tier_definitions (program_id, tier_name) where status = 'published';
create unique index ltd_single_published_rank on app.loyalty_tier_definitions (program_id, tier_rank) where status = 'published';

create function app.touch_loyalty_tier_definition_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_tier_definitions_touch_row
  before update on app.loyalty_tier_definitions
  for each row
  execute function app.touch_loyalty_tier_definition_row();

-- ===========================================================================
-- 2. app.loyalty_account_tier_movements -- APPEND-ONLY. Current tier is
-- DERIVED as the latest row per loyalty_account_id (design decision 15's own
-- business rule) -- never stored as a mutable field anywhere.
-- ===========================================================================

create table app.loyalty_account_tier_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  from_tier_id uuid references app.loyalty_tier_definitions (id),
  to_tier_id uuid not null references app.loyalty_tier_definitions (id),
  movement_type text not null,
  tier_definition_version_id uuid not null references app.loyalty_tier_definitions (id),
  evaluation_snapshot jsonb not null,
  reason text,
  next_review_at timestamptz not null,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  constraint latm_movement_type_check check (movement_type in ('initial', 'upgrade', 'downgrade')),
  constraint latm_snapshot_check check (jsonb_typeof(evaluation_snapshot) = 'object'),
  constraint latm_initial_shape_check check (movement_type <> 'initial' or from_tier_id is null),
  constraint latm_change_shape_check check (movement_type = 'initial' or from_tier_id is not null),
  constraint latm_version_id_matches_to_tier_check check (tier_definition_version_id = to_tier_id)
);

comment on table app.loyalty_account_tier_movements is
  'CPL-317: append-only, no UPDATE/DELETE grant to any non-service_role caller anywhere in this migration -- a correction is always a NEW movement row, never an edit. evaluation_snapshot records the source numbers (computed amount, window, dimension, eligible tier) that justified this exact movement, permanently, even if a LATER tier definition version changes what a NEW recalculation would produce (design decision 11: created_at defaults to clock_timestamp(), the self-found CPL-315 ordering-defect class, applied proactively). next_review_at is the grace-period end this movement itself grants (design decision 4) -- self-contained, never recomputed from a tier definition''s current review_period_days on a later call.';

create index latm_tenant_account_created_idx on app.loyalty_account_tier_movements (tenant_id, loyalty_account_id, created_at desc, id desc);
create index latm_tenant_created_id_idx on app.loyalty_account_tier_movements (tenant_id, created_at desc, id desc);
create index latm_to_tier_idx on app.loyalty_account_tier_movements (to_tier_id);

-- ===========================================================================
-- 3. app.loyalty_account_tier_holds -- ONE row per loyalty_account_id,
-- created lazily on first hold (design decision 6). Orthogonal to tier
-- tracking (design decision 5).
-- ===========================================================================

create table app.loyalty_account_tier_holds (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  is_held boolean not null default false,
  hold_reason text,
  held_by text,
  held_at timestamptz,
  released_by text,
  released_at timestamptz,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lath_tenant_account_unique unique (tenant_id, loyalty_account_id),
  constraint lath_held_shape_check check ((is_held = false) or (hold_reason is not null and held_by is not null and held_at is not null))
);

comment on table app.loyalty_account_tier_holds is
  'CPL-317: fraud-hold/dispute-hold mechanism (design decision 6, this prompt''s own precedent option (a)) -- suspends a held account''s TIER BENEFITS as surfaced by app.list_customer_portal_loyalty_tier_cards (an empty benefits object plus a customer-safe generic message, never the real hold_reason). Never alters CPL-316''s own app.loyalty_accounts. Genuinely mutable (unlike the two append-only tables above) -- exactly one row per loyalty_account_id, upserted by app.hold_loyalty_account_tier_benefits/app.release_loyalty_account_tier_benefits.';

create index lath_tenant_account_idx on app.loyalty_account_tier_holds (tenant_id, loyalty_account_id);

create function app.touch_loyalty_account_tier_hold_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_account_tier_holds_touch_row
  before update on app.loyalty_account_tier_holds
  for each row
  execute function app.touch_loyalty_account_tier_hold_row();

-- ===========================================================================
-- 4. app.create_loyalty_tier_definition -- staff, LYL:Create
-- ===========================================================================

create function app.create_loyalty_tier_definition(
  p_tenant_id uuid,
  p_program_id uuid,
  p_tier_name text,
  p_tier_rank integer,
  p_threshold_dimension text,
  p_threshold_value numeric,
  p_benefits jsonb,
  p_review_period_days integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_tier_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
  v_next_version integer;
  v_tier app.loyalty_tier_definitions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_tier_name is null or length(trim(p_tier_name)) = 0 then
    raise exception 'invalid_tier_name: a non-empty tier name is required' using errcode = 'check_violation';
  end if;
  if p_tier_rank is null or p_tier_rank <= 0 then
    raise exception 'invalid_tier_rank: tier_rank must be a positive integer, got %', p_tier_rank using errcode = 'check_violation';
  end if;
  if p_threshold_dimension is null or length(trim(p_threshold_dimension)) = 0 then
    raise exception 'invalid_threshold_dimension: a non-empty threshold dimension is required' using errcode = 'check_violation';
  end if;
  if p_threshold_value is null or p_threshold_value < 0 then
    raise exception 'invalid_threshold_value: threshold_value must be non-negative, got %', p_threshold_value using errcode = 'check_violation';
  end if;
  if p_benefits is not null and jsonb_typeof(p_benefits) <> 'object' then
    raise exception 'invalid_benefits: benefits must be a JSON object' using errcode = 'check_violation';
  end if;
  if p_review_period_days is not null and p_review_period_days < 0 then
    raise exception 'invalid_review_period_days: review_period_days must be non-negative, got %', p_review_period_days using errcode = 'check_violation';
  end if;

  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_not_found: %', p_program_id using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version
    from app.loyalty_tier_definitions where program_id = p_program_id and tier_name = trim(p_tier_name);

  begin
    insert into app.loyalty_tier_definitions (
      tenant_id, program_id, tier_name, tier_rank, threshold_dimension, threshold_value, benefits, review_period_days, version_number, created_by
    ) values (
      p_tenant_id, p_program_id, trim(p_tier_name), p_tier_rank, trim(p_threshold_dimension), p_threshold_value,
      coalesce(p_benefits, '{}'::jsonb), coalesce(p_review_period_days, 0), v_next_version, p_actor_label
    )
    returning * into v_tier;
  exception
    when unique_violation then
      raise exception 'draft_already_exists: program % tier % already has an open draft version', p_program_id, trim(p_tier_name) using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_loyalty_tier_definition',
    'app.loyalty_tier_definitions', v_tier.id, 'success', null, null, to_jsonb(v_tier)
  );

  return v_tier;
end;
$$;

comment on function app.create_loyalty_tier_definition is
  'CPL-317: at most one draft per (program, tier_name) at a time (ltd_single_draft_per_tier) -- a real exception-handler-backed check, not a pre-check-only pattern.';

-- ===========================================================================
-- 5. app.update_loyalty_tier_definition_draft -- staff, LYL:Edit, draft-only
-- ===========================================================================

create function app.update_loyalty_tier_definition_draft(
  p_tenant_id uuid,
  p_tier_definition_id uuid,
  p_expected_version integer,
  p_tier_name text,
  p_tier_rank integer,
  p_threshold_dimension text,
  p_threshold_value numeric,
  p_benefits jsonb,
  p_review_period_days integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_tier_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tier app.loyalty_tier_definitions;
  v_updated app.loyalty_tier_definitions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_tier_name is null or length(trim(p_tier_name)) = 0 then
    raise exception 'invalid_tier_name: a non-empty tier name is required' using errcode = 'check_violation';
  end if;
  if p_tier_rank is null or p_tier_rank <= 0 then
    raise exception 'invalid_tier_rank: tier_rank must be a positive integer, got %', p_tier_rank using errcode = 'check_violation';
  end if;
  if p_threshold_dimension is null or length(trim(p_threshold_dimension)) = 0 then
    raise exception 'invalid_threshold_dimension: a non-empty threshold dimension is required' using errcode = 'check_violation';
  end if;
  if p_threshold_value is null or p_threshold_value < 0 then
    raise exception 'invalid_threshold_value: threshold_value must be non-negative, got %', p_threshold_value using errcode = 'check_violation';
  end if;
  if p_benefits is not null and jsonb_typeof(p_benefits) <> 'object' then
    raise exception 'invalid_benefits: benefits must be a JSON object' using errcode = 'check_violation';
  end if;
  if p_review_period_days is not null and p_review_period_days < 0 then
    raise exception 'invalid_review_period_days: review_period_days must be non-negative, got %', p_review_period_days using errcode = 'check_violation';
  end if;

  select * into v_tier from app.loyalty_tier_definitions where id = p_tier_definition_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_tier_definition_not_found: %', p_tier_definition_id using errcode = 'no_data_found';
  end if;

  if v_tier.record_version <> p_expected_version then
    raise exception 'stale_version: tier definition % expected version % but found %', p_tier_definition_id, p_expected_version, v_tier.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_tier.status <> 'draft' then
    raise exception 'invalid_transition: tier definition % is % -- only a draft may be edited', p_tier_definition_id, v_tier.status
      using errcode = 'check_violation';
  end if;

  begin
    update app.loyalty_tier_definitions
    set tier_name = trim(p_tier_name), tier_rank = p_tier_rank, threshold_dimension = trim(p_threshold_dimension),
        threshold_value = p_threshold_value, benefits = coalesce(p_benefits, '{}'::jsonb), review_period_days = coalesce(p_review_period_days, 0)
    where id = p_tier_definition_id and record_version = p_expected_version
    returning * into v_updated;
  exception
    when unique_violation then
      raise exception 'draft_already_exists: program % tier % already has a different open draft version', v_tier.program_id, trim(p_tier_name) using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: tier definition % was concurrently modified (expected version %)', p_tier_definition_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_loyalty_tier_definition_draft',
    'app.loyalty_tier_definitions', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 6. app.publish_loyalty_tier_definition -- staff, LYL:Configure (design
-- decision 13's elevated action). Supersedes the SAME (program_id,
-- tier_name)'s own prior published version, if any, in the SAME transaction.
-- ===========================================================================

create function app.publish_loyalty_tier_definition(
  p_tenant_id uuid,
  p_tier_definition_id uuid,
  p_expected_version integer,
  p_effective_from timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_tier_definitions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tier app.loyalty_tier_definitions;
  v_prior_published app.loyalty_tier_definitions;
  v_effective_from timestamptz;
  v_published app.loyalty_tier_definitions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tier from app.loyalty_tier_definitions where id = p_tier_definition_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_tier_definition_not_found: %', p_tier_definition_id using errcode = 'no_data_found';
  end if;

  if v_tier.record_version <> p_expected_version then
    raise exception 'stale_version: tier definition % expected version % but found %', p_tier_definition_id, p_expected_version, v_tier.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_tier.status <> 'draft' then
    raise exception 'invalid_transition: tier definition % is % -- only a draft may be published', p_tier_definition_id, v_tier.status
      using errcode = 'check_violation';
  end if;

  v_effective_from := coalesce(p_effective_from, clock_timestamp());

  select * into v_prior_published from app.loyalty_tier_definitions
    where program_id = v_tier.program_id and tier_name = v_tier.tier_name and status = 'published' for update;
  if found then
    update app.loyalty_tier_definitions
      set status = 'superseded', effective_to = v_effective_from
      where id = v_prior_published.id;
  end if;

  begin
    update app.loyalty_tier_definitions
      set status = 'published', published_by = p_actor_label, published_at = clock_timestamp(), effective_from = v_effective_from
      where id = p_tier_definition_id and record_version = p_expected_version
      returning * into v_published;
  exception
    when unique_violation then
      raise exception 'tier_rank_conflict: rank % is already held by another published tier of program %', v_tier.tier_rank, v_tier.program_id using errcode = 'check_violation';
  end;
  if not found then
    raise exception 'stale_version: tier definition % was concurrently modified (expected version %)', p_tier_definition_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_published.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_loyalty_tier_definition',
    'app.loyalty_tier_definitions', v_published.id, 'success', null,
    case when v_prior_published.id is not null then jsonb_build_object('supersedes_tier_definition_id', v_prior_published.id) else null end,
    to_jsonb(v_published)
  );

  return v_published;
end;
$$;

-- ===========================================================================
-- 7. app.get_loyalty_tier_definition / app.list_loyalty_tier_definitions --
-- staff, LYL:View
-- ===========================================================================

create function app.get_loyalty_tier_definition(p_tenant_id uuid, p_tier_definition_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_tier_definitions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_tier app.loyalty_tier_definitions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_tier from app.loyalty_tier_definitions where id = p_tier_definition_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_tier_definition_not_found: %', p_tier_definition_id using errcode = 'no_data_found';
  end if;

  return v_tier;
end;
$$;

create function app.list_loyalty_tier_definitions(
  p_tenant_id uuid,
  p_program_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_tier_definitions
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
  select t.* from app.loyalty_tier_definitions t
  where t.tenant_id = p_tenant_id
    and (p_program_id is null or t.program_id = p_program_id)
    and (p_status is null or t.status = p_status)
    and (p_cursor_id is null or (t.updated_at, t.id) < (p_cursor_updated_at, p_cursor_id))
  order by t.updated_at desc, t.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 8. app.recalculate_customer_loyalty_tier -- staff/system, LYL:Edit. The ONE
-- tier-movement-posting entry point (design decisions 1, 4, 5, 7, 8, 10, 11).
-- ===========================================================================

create function app.recalculate_customer_loyalty_tier(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_account_tier_movements
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_loyalty_account app.loyalty_accounts;
  v_current_movement app.loyalty_account_tier_movements;
  v_current_def app.loyalty_tier_definitions;
  v_window_start timestamptz;
  v_amount numeric;
  v_eligible app.loyalty_tier_definitions;
  v_movement_type text;
  v_next_review_at timestamptz;
  v_snapshot jsonb;
  v_reason text;
  v_new app.loyalty_account_tier_movements;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_loyalty_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;
  if v_loyalty_account.status = 'closed' then
    raise exception 'loyalty_account_closed: % is closed -- tier recalculation does not apply to a closed account', p_loyalty_account_id using errcode = 'check_violation';
  end if;

  -- Design decision 10: serialize concurrent recalculation calls for the
  -- SAME account (salt 3, this migration's own dedicated advisory-lock
  -- domain, mirrors 20260730320000's hashtextextended(id::text, salt)
  -- precedent).
  perform pg_advisory_xact_lock(hashtextextended(p_loyalty_account_id::text, 3));

  select * into v_current_movement from app.loyalty_account_tier_movements
    where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id
    order by created_at desc, id desc limit 1;
  if v_current_movement.id is not null then
    select * into v_current_def from app.loyalty_tier_definitions where id = v_current_movement.to_tier_id;
  end if;

  -- Design decision 7: unsupported dimension raises loudly, BEFORE eligible-
  -- tier resolution, rather than being silently excluded from consideration.
  if exists (
    select 1 from app.loyalty_tier_definitions
    where tenant_id = p_tenant_id and program_id = v_loyalty_account.program_id and status = 'published'
      and threshold_dimension <> 'earning_amount_ytd'
  ) then
    raise exception 'unsupported_threshold_dimension: program % has a published tier definition using an unsupported threshold_dimension', v_loyalty_account.program_id
      using errcode = 'check_violation';
  end if;

  v_window_start := date_trunc('year', now());
  select coalesce(sum(amount), 0) into v_amount
    from app.loyalty_earning_events
    where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id and created_at >= v_window_start;

  select * into v_eligible from app.loyalty_tier_definitions
    where tenant_id = p_tenant_id and program_id = v_loyalty_account.program_id and status = 'published'
      and threshold_value <= v_amount
    order by tier_rank desc limit 1;
  if not found then
    raise exception 'no_eligible_tier_definition: no published tier definition of program % qualifies for computed amount %', v_loyalty_account.program_id, v_amount
      using errcode = 'no_data_found';
  end if;

  if v_current_movement.id is null then
    v_movement_type := 'initial';
    v_reason := 'Initial tier assignment.';
  elsif v_eligible.id = v_current_movement.to_tier_id then
    -- Design decision 10: behavioral idempotency -- eligible tier unchanged, safe no-op.
    return v_current_movement;
  elsif v_eligible.tier_rank > v_current_def.tier_rank then
    v_movement_type := 'upgrade';
    v_reason := 'Recalculated: earning newly qualifies for a higher tier.';
  else
    -- Design decision 4: downgrade candidate, gated on the CURRENT movement's
    -- own stamped grace window.
    if now() < v_current_movement.next_review_at then
      return v_current_movement;
    end if;
    v_movement_type := 'downgrade';
    v_reason := 'Recalculated: earning is below the current tier''s own threshold and the review period has elapsed.';
  end if;

  v_snapshot := jsonb_build_object(
    'window_start', v_window_start,
    'window_end', now(),
    'threshold_dimension', 'earning_amount_ytd',
    'computed_amount', v_amount,
    'eligible_tier_id', v_eligible.id,
    'eligible_tier_name', v_eligible.tier_name,
    'eligible_tier_rank', v_eligible.tier_rank,
    'eligible_threshold_value', v_eligible.threshold_value,
    'previous_tier_id', v_current_movement.to_tier_id
  );

  v_next_review_at := clock_timestamp() + make_interval(days => v_eligible.review_period_days);

  insert into app.loyalty_account_tier_movements (
    tenant_id, loyalty_account_id, from_tier_id, to_tier_id, movement_type, tier_definition_version_id,
    evaluation_snapshot, reason, next_review_at, created_by
  ) values (
    p_tenant_id, p_loyalty_account_id,
    case when v_movement_type = 'initial' then null else v_current_movement.to_tier_id end,
    v_eligible.id, v_movement_type, v_eligible.id, v_snapshot, v_reason, v_next_review_at, p_actor_label
  )
  returning * into v_new;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'recalculate_customer_loyalty_tier',
    'app.loyalty_account_tier_movements', v_new.id, 'success', null,
    case when v_current_movement.id is not null then jsonb_build_object('from_tier_id', v_current_movement.to_tier_id) else null end,
    jsonb_build_object('to_tier_id', v_eligible.id, 'movement_type', v_movement_type, 'computed_amount', v_amount)
  );

  return v_new;
end;
$$;

comment on function app.recalculate_customer_loyalty_tier is
  'CPL-317: idempotent by construction (design decision 10) -- calling this repeatedly with no underlying change in eligibility is a safe no-op, never a spurious movement row. Upgrades apply immediately; downgrades are gated on the current movement''s own stamped next_review_at (design decision 4). On-demand/staff-triggered only in this checkpoint -- no automatic job/trigger wiring (design decision 14, ISS-2026-127).';

-- ===========================================================================
-- 9. app.hold_loyalty_account_tier_benefits / app.release_loyalty_account_
-- tier_benefits -- staff, LYL:Configure (design decision 13's elevated
-- action, a governed benefit-suspension action).
-- ===========================================================================

create function app.hold_loyalty_account_tier_benefits(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_account_tier_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_hold app.loyalty_account_tier_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to hold a loyalty account''s tier benefits' using errcode = 'not_null_violation';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  select * into v_hold from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id for update;
  if found and v_hold.is_held then
    return v_hold;
  end if;

  if found then
    update app.loyalty_account_tier_holds
      set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = clock_timestamp(), released_by = null, released_at = null
      where id = v_hold.id
      returning * into v_hold;
  else
    begin
      insert into app.loyalty_account_tier_holds (tenant_id, loyalty_account_id, is_held, hold_reason, held_by, held_at)
      values (p_tenant_id, p_loyalty_account_id, true, p_reason, p_actor_label, clock_timestamp())
      returning * into v_hold;
    exception
      when unique_violation then
        select * into v_hold from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id for update;
        if v_hold.is_held then
          return v_hold;
        end if;
        update app.loyalty_account_tier_holds
          set is_held = true, hold_reason = p_reason, held_by = p_actor_label, held_at = clock_timestamp(), released_by = null, released_at = null
          where id = v_hold.id
          returning * into v_hold;
    end;
  end if;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'hold_loyalty_account_tier_benefits',
    'app.loyalty_account_tier_holds', v_hold.id, 'success', p_reason, null, jsonb_build_object('is_held', true)
  );

  return v_hold;
end;
$$;

comment on function app.hold_loyalty_account_tier_benefits is
  'CPL-317: idempotent -- holding an already-held account is a safe no-op returning the unchanged row (original hold_reason/held_by/held_at preserved, never overwritten by a repeated call). A held account''s benefits are suppressed in app.list_customer_portal_loyalty_tier_cards (proven live in this checkpoint''s own db-test).';

create function app.release_loyalty_account_tier_benefits(
  p_tenant_id uuid,
  p_loyalty_account_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_account_tier_holds
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_hold app.loyalty_account_tier_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_hold from app.loyalty_account_tier_holds where tenant_id = p_tenant_id and loyalty_account_id = p_loyalty_account_id for update;
  if not found then
    raise exception 'loyalty_account_tier_hold_not_found: no hold exists for loyalty account %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;
  if not v_hold.is_held then
    return v_hold;
  end if;

  update app.loyalty_account_tier_holds
    set is_held = false, released_by = p_actor_label, released_at = clock_timestamp()
    where id = v_hold.id
    returning * into v_hold;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'release_loyalty_account_tier_benefits',
    'app.loyalty_account_tier_holds', v_hold.id, 'success', null, null, jsonb_build_object('is_held', false)
  );

  return v_hold;
end;
$$;

-- ===========================================================================
-- 10. app.get_loyalty_account_tier_state / app.list_loyalty_account_tier_
-- movements -- staff, LYL:View (full internal projection)
-- ===========================================================================

create function app.get_loyalty_account_tier_state(p_tenant_id uuid, p_loyalty_account_id uuid, p_actor_auth_user_id uuid)
returns table (
  loyalty_account_id uuid,
  current_tier_id uuid,
  current_tier_name text,
  current_tier_rank integer,
  movement_type text,
  next_review_at timestamptz,
  tier_since timestamptz,
  is_held boolean,
  hold_reason text,
  held_by text,
  held_at timestamptz
)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_movement app.loyalty_account_tier_movements;
  v_tier app.loyalty_tier_definitions;
  v_hold app.loyalty_account_tier_holds;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_loyalty_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_loyalty_account_id using errcode = 'no_data_found';
  end if;

  -- Table aliases + explicit qualification are mandatory here (not merely
  -- style): this function's own RETURNS TABLE clause implicitly declares
  -- loyalty_account_id/is_held/hold_reason/held_by/held_at as PL/pgSQL
  -- variables in scope, so a bare, unqualified reference to any of those
  -- names inside a query would be genuinely ambiguous between that
  -- variable and the identically-named table column.
  select m.* into v_movement from app.loyalty_account_tier_movements m
    where m.tenant_id = p_tenant_id and m.loyalty_account_id = p_loyalty_account_id
    order by m.created_at desc, m.id desc limit 1;
  if v_movement.id is not null then
    select * into v_tier from app.loyalty_tier_definitions where id = v_movement.to_tier_id;
  end if;
  select h.* into v_hold from app.loyalty_account_tier_holds h where h.tenant_id = p_tenant_id and h.loyalty_account_id = p_loyalty_account_id;

  return query
  select
    v_account.id, v_tier.id, v_tier.tier_name, v_tier.tier_rank, v_movement.movement_type, v_movement.next_review_at, v_movement.created_at,
    coalesce(v_hold.is_held, false), v_hold.hold_reason, v_hold.held_by, v_hold.held_at;
end;
$$;

create function app.list_loyalty_account_tier_movements(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_account_tier_movements
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
  select m.* from app.loyalty_account_tier_movements m
  where m.tenant_id = p_tenant_id
    and (p_loyalty_account_id is null or m.loyalty_account_id = p_loyalty_account_id)
    and (p_cursor_id is null or (m.created_at, m.id) < (p_cursor_created_at, p_cursor_id))
  order by m.created_at desc, m.id desc
  limit v_limit;
end;
$$;

comment on function app.list_loyalty_account_tier_movements is
  'CPL-317: keyset-paginated on (created_at desc, id desc) -- app.loyalty_account_tier_movements has no updated_at column (append-only, immutable rows), so created_at is the equivalent stable keyset field.';

-- ===========================================================================
-- 11. app.list_customer_portal_loyalty_tier_cards -- customer-facing (Layer
-- 4, ADR-0024 Part A). Deny-by-default. A held account's benefits are
-- suppressed (design decision 6).
-- ===========================================================================

create function app.list_customer_portal_loyalty_tier_cards(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_account_id uuid default null,
  p_limit integer default 50
)
returns table (
  loyalty_account_id uuid,
  customer_account_id uuid,
  program_id uuid,
  program_name text,
  current_tier_id uuid,
  current_tier_name text,
  current_tier_rank integer,
  benefits jsonb,
  is_benefits_suspended boolean,
  benefits_suspended_reason text,
  computed_amount numeric,
  next_tier_id uuid,
  next_tier_name text,
  next_tier_threshold numeric,
  amount_to_next_tier numeric,
  next_review_at timestamptz,
  tier_since timestamptz
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
  with latest_movement as (
    select distinct on (m.loyalty_account_id) m.*
    from app.loyalty_account_tier_movements m
    where m.tenant_id = p_tenant_id
    order by m.loyalty_account_id, m.created_at desc, m.id desc
  ),
  window_sum as (
    select e.loyalty_account_id, coalesce(sum(e.amount), 0) as amount
    from app.loyalty_earning_events e
    where e.tenant_id = p_tenant_id and e.created_at >= date_trunc('year', now())
    group by e.loyalty_account_id
  )
  select
    la.id,
    la.customer_account_id,
    la.program_id,
    p.name,
    ct.id,
    ct.tier_name,
    ct.tier_rank,
    case when coalesce(h.is_held, false) then '{}'::jsonb else coalesce(ct.benefits, '{}'::jsonb) end,
    coalesce(h.is_held, false),
    case when coalesce(h.is_held, false) then 'Your loyalty tier benefits are temporarily on hold. Contact your account administrator or support for details.' else null end,
    coalesce(ws.amount, 0),
    nt.id,
    nt.tier_name,
    nt.threshold_value,
    case when nt.id is not null then greatest(nt.threshold_value - coalesce(ws.amount, 0), 0) else null end,
    lm.next_review_at,
    lm.created_at
  from app.loyalty_accounts la
  join app.loyalty_programs p on p.id = la.program_id
  left join latest_movement lm on lm.loyalty_account_id = la.id
  left join app.loyalty_tier_definitions ct on ct.id = lm.to_tier_id
  left join window_sum ws on ws.loyalty_account_id = la.id
  left join app.loyalty_account_tier_holds h on h.tenant_id = p_tenant_id and h.loyalty_account_id = la.id
  left join lateral (
    select td.id, td.tier_name, td.threshold_value
    from app.loyalty_tier_definitions td
    where td.tenant_id = p_tenant_id and td.program_id = la.program_id and td.status = 'published'
      and td.tier_rank > coalesce(ct.tier_rank, 0)
    order by td.tier_rank asc
    limit 1
  ) nt on true
  where la.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and la.status = 'active'
    and (p_customer_account_id is null or la.customer_account_id = p_customer_account_id)
  order by la.updated_at desc, la.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_tier_cards is
  'CPL-317: customer-safe tier-card projection -- current tier, benefits (suppressed to {} plus a generic customer-safe message when held, NEVER the real internal hold_reason), progress toward the next published tier, and the account''s own next_review_at (the review/expiry date this prompt''s own UI/UX impact requires). Deny-by-default: an out-of-scope p_customer_account_id or an empty resolved scope both return zero rows, never an error. Only active loyalty accounts are shown -- a closed enrollment carries no ongoing tier card.';

-- ===========================================================================
-- 12. RLS -- enable, grant service_role only (design decision 16).
-- ===========================================================================

alter table app.loyalty_tier_definitions enable row level security;
alter table app.loyalty_account_tier_movements enable row level security;
alter table app.loyalty_account_tier_holds enable row level security;

grant select, insert, update, delete on app.loyalty_tier_definitions, app.loyalty_account_tier_holds to service_role;
grant select, insert on app.loyalty_account_tier_movements to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.create_loyalty_tier_definition(uuid, uuid, text, integer, text, numeric, jsonb, integer, uuid, text) to authenticated, service_role;
grant execute on function app.update_loyalty_tier_definition_draft(uuid, uuid, integer, text, integer, text, numeric, jsonb, integer, uuid, text) to authenticated, service_role;
grant execute on function app.publish_loyalty_tier_definition(uuid, uuid, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_tier_definition(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_tier_definitions(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.recalculate_customer_loyalty_tier(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.hold_loyalty_account_tier_benefits(uuid, uuid, text, uuid, text) to authenticated, service_role;
grant execute on function app.release_loyalty_account_tier_benefits(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_account_tier_state(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_account_tier_movements(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_tier_cards(uuid, uuid, uuid, integer) to authenticated, service_role;
