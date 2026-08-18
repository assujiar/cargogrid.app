-- Phase 8 capability CPL-316 (CG-S13-CPL-018, Prompt 316, "Loyalty Program and
-- Earning") -- the FIRST-EVER Loyalty domain schema in this repository
-- (zero `loyalty`/`points_ledger`/`membership_tier`/`cashback`/`voucher`/
-- `redemption` table, contract, or route anywhere before this migration --
-- confirmed by grep, per ADR-0024 Part D's own greenfield confirmation).
-- Read docs/adr/ADR-0024-phase8-customer-portal-access-and-transport-pattern.md
-- Part D, supabase/migrations/20260730190000_create_advanced_tms_inventory_
-- ledger.sql, supabase/migrations/20260731010000_bind_hris_payroll_to_finance_
-- handoff.sql, and supabase/migrations/20260729100000_create_finance_accounts_
-- receivable.sql in full before writing any of this file.
--
-- CONFIRMED (not assumed): app.finance_ar_open_items.status is a plain,
-- procedurally-maintained `text` column (`status text not null default
-- 'open'`, `finance_ar_open_items_status_check`), computed and written
-- directly by `app.apply_finance_ar_allocation`/`app.reverse_finance_ar_
-- allocation` via an ordinary `UPDATE ... SET status = v_new_status` --
-- NOT a generated column (only `open_amount` on that table is generated:
-- `generated always as (original_amount - allocated_amount) stored`). This
-- migration's own earning evaluator therefore reads `status`/`is_held`
-- exactly as any other plain column, no special generated-column handling
-- required.
--
-- ===========================================================================
-- Design decisions (disclosed, not re-derived)
-- ===========================================================================
--
-- 1. **"The customer's active loyalty_account" (singular) is made real and
--    deterministic by a partial unique index, resolving a genuine ambiguity
--    this prompt's own given RPC signature creates.** `app.evaluate_
--    customer_loyalty_earning_for_paid_invoice(p_tenant_id, p_ar_open_item_id,
--    p_actor_auth_user_id, p_actor_label)` carries no `p_program_id`
--    parameter at all -- so which program applies when a customer could in
--    principle be enrolled in more than one? This migration's own literal
--    schema instruction gives `app.loyalty_accounts` a `unique (tenant_id,
--    customer_account_id, program_id)` constraint alone, which does NOT by
--    itself prevent two SIMULTANEOUSLY ACTIVE enrollments in two different
--    programs for the same customer account. This migration adds a second,
--    stronger constraint on top of the literal one: `loyalty_accounts_
--    single_active_per_customer`, a partial unique index on `(tenant_id,
--    customer_account_id) where status = 'active'` -- at most one ACTIVE
--    loyalty enrollment per customer account, at a time, tenant-wide. This
--    is a genuine, disclosed business-rule decision (most B2B logistics
--    loyalty programs are single-program-at-a-time per customer, not
--    simultaneous multi-program membership), not an oversight, and it is
--    exactly what makes the given RPC signature's own singular "the
--    customer's active loyalty_account" / "the program's currently
--    published rule version" phrasing well-defined and race-safe. A
--    customer MAY still hold multiple HISTORICAL (suspended/closed) rows
--    across different programs -- only the ACTIVE slot is exclusive.
-- 2. **Every actor-taking function in this migration calls `app.assert_
--    actor_is_session_identity` as its own literal FIRST statement** --
--    the batch's own single most common Critical defect class, applied from
--    the first draft.
-- 3. **A genuine hardening beyond the "fetch row, then check authority"
--    precedent CPL-314/HRT-282 established elsewhere in this batch: every
--    staff mutate/get-by-id RPC here takes `p_tenant_id` as an explicit
--    parameter and checks `LYL:*` authority FIRST, before ever fetching the
--    target row.** CPL-314's own fetch-then-check shape was necessary there
--    only because its functions had no `p_tenant_id` parameter and needed it
--    FROM the row to run the authority check at all. This migration's own
--    signatures always carry `p_tenant_id`, so there is no structural reason
--    to fetch first -- doing the authority check first is strictly safer
--    (C-05: never reveals a row's real existence/tenant via a distinguishable
--    error before authority is established) and is applied uniformly across
--    every staff RPC below (`get_loyalty_program`, `update_loyalty_program_
--    status`, `create_loyalty_program_rule_version`, `update_loyalty_program_
--    rule_version_draft`, `publish_loyalty_program_rule_version`, `enroll_
--    customer_loyalty_account`, `set_loyalty_account_status`, `evaluate_
--    customer_loyalty_earning_for_paid_invoice`, `reverse_loyalty_earning_
--    event`, `get_loyalty_earning_event`).
-- 4. **LYL permission mapping.** `app.permissions` (PLT-111) already seeds
--    exactly four LYL actions: `View`/`Create`/`Edit` (`standard`) and
--    `Configure` (`admin`) -- confirmed by direct read
--    (`20260716103445_create_roles_permissions.sql:71-72`) before writing
--    this migration, not assumed. Unlike FIN/COM/HRS/PRC, LYL has NO
--    `Approve` action. This migration maps: ordinary config CRUD (create
--    program, create/edit a rule version DRAFT, enroll, suspend/reactivate/
--    close an account) to `Create`/`Edit`; ordinary ledger posting (`evaluate_
--    customer_loyalty_earning_for_paid_invoice`) to `Edit`, mirroring FIN's
--    own `post_finance_ar_open_item`/`apply_finance_ar_allocation` use of
--    `FIN:Edit` for ordinary posting; and the two highest-privilege,
--    governance-grade actions in this capability -- PUBLISHING a rule version
--    (locks it forever, supersedes the prior published version, changes what
--    every future paid invoice earns) and REVERSING an already-recorded
--    earning event (a governed ledger correction) -- both to `LYL:Configure`,
--    the module's own `admin`-category action, mirroring FIN's own use of
--    the elevated `FIN:Approve` for `app.publish_finance_config_version`/
--    `app.reverse_finance_ar_allocation` where LYL simply has no distinct
--    `Approve` action to reach for.
-- 5. **No derived balance table is built here.** This migration owns program
--    config + rule versioning + the raw, append-only earning EVENT record
--    only -- `app.loyalty_earning_events` is the generic, reward-type-tagged
--    ledger every subsequent Loyalty prompt reads from. A derived points
--    balance (CPL-317/318, tiers/points) and a derived cashback/voucher
--    balance (CPL-319) are each that later prompt's own scope, explicitly
--    per this prompt's own instructions -- never invented here.
-- 6. **No `currency` column on `app.loyalty_earning_events`** -- matches this
--    prompt's own literal, given column list exactly (`tenant_id,
--    loyalty_account_id, program_id, rule_version_id, reward_type, amount,
--    source_type, source_id, idempotency_key, corrects_event_id, reason,
--    created_by, created_at` -- no currency field named). `reward_type =
--    'points'` is currency-less by nature; `reward_type = 'cashback'` is
--    implicitly denominated in its own source `app.finance_ar_open_items.
--    currency` (reachable via `source_id`, never duplicated onto this table).
--    A multi-currency cashback rollup, if ever needed, is CPL-319's own scope.
-- 7. **`earning_basis` is free `text` at the schema level (matches the given
--    literal type exactly: "text (e.g. 'per_paid_invoice_amount')"), but
--    `app.evaluate_customer_loyalty_earning_for_paid_invoice` only
--    IMPLEMENTS computation for the one named basis, `'per_paid_invoice_
--    amount'`.** Any other value is a real, structurally valid row (a future
--    prompt/migration may teach the evaluator a new basis additively) but
--    raises a clear `unsupported_earning_basis` error at evaluation time
--    rather than silently mis-computing or defaulting to zero -- a disclosed,
--    bounded implementation, not a silent gap.
-- 8. **`eligibility_config` interprets exactly one key today: `min_invoice_
--    amount`** (numeric, optional) -- a minimum paid-invoice-amount gate. The
--    column is forward-extensible `jsonb` for future Loyalty prompts (317
--    tiers, etc.) to add their own keys additively; this migration reads
--    only the one key it implements, ignoring any other key present.
-- 9. **On-demand/staff-triggered earning evaluation only -- NO automatic job
--    or trigger wiring in this checkpoint, disclosed plainly (not a silent
--    gap).** `app.apply_finance_ar_allocation` (FIN-198, the one function
--    that ever flips `app.finance_ar_open_items.status` to `'paid'`) is an
--    already-APPLIED migration this task may not edit. The only additive
--    alternative -- a new `AFTER UPDATE` trigger this migration attaches
--    directly onto Finance's own `app.finance_ar_open_items` table -- would
--    make Loyalty logic fire silently inside a Finance-owned write path with
--    no Finance-side review point, the exact kind of unreviewed cross-domain
--    coupling ADR-0024 Part D's own handoff discipline (`prepare_finance_*_
--    from_*`, "read another domain's already-committed state, never write
--    into it") is designed to avoid. Registered as `ISS-2026-126`
--    (`docs/runtime/KNOWN_ISSUES.md`) rather than silently left: earning
--    evaluation today is invoked on demand (a staff/tenant-admin action in
--    this checkpoint's own new admin UI) via `app.evaluate_customer_loyalty_
--    earning_for_paid_invoice`, which is itself a real, complete, idempotent,
--    fully-working RPC -- the trigger MECHANISM is what is deferred, not the
--    evaluation logic itself.
-- 10. **Reversal is a full reversal only, at most one reversal per original
--    event** -- mirrors `app.reverse_inventory_movement`'s own bounded shape
--    (`already_reversed`/"a reversal may not itself be reversed") exactly.
--    Partial reversal is not this prompt's own chartered scope.
-- 11. **Mandatory ledger-posting discipline applied to both `app.evaluate_
--    customer_loyalty_earning_for_paid_invoice` and `app.reverse_loyalty_
--    earning_event`**: a real, deterministic (never client-`Date.now()`-based)
--    idempotency key (`'ar-open-item:' || p_ar_open_item_id::text` for
--    earning; a caller-supplied, expected-deterministic key for reversal,
--    mirroring `app.reverse_inventory_movement`'s own `p_idempotency_key`
--    parameter shape), a genuine `unique (tenant_id, idempotency_key)`
--    constraint on `app.loyalty_earning_events`, the authority check running
--    BEFORE the idempotent short-circuit `SELECT`, and a real `exception
--    when unique_violation` handler around each `INSERT` -- never a
--    pre-check-only pattern. `app.enroll_customer_loyalty_account` applies
--    the identical discipline against its own natural key (`tenant_id,
--    customer_account_id, program_id`).
-- 12. **Never mutate a derived/ledger row outside its own owning function,
--    never delete/rewrite a posted `app.loyalty_earning_events` row.** No
--    `UPDATE`/`DELETE` grant on that table to `authenticated`; no function in
--    this migration ever issues `UPDATE`/`DELETE` against it. A correction is
--    always a NEW, linked row (`corrects_event_id`), mirroring `app.
--    inventory_movements.corrects_movement_id` exactly.
-- 13. **RLS: `authenticated` holds ZERO direct grant** on any of the 4 new
--    tables, mirroring every other table in this batch -- the RPCs below are
--    the only sanctioned access path, for both staff and customer callers.
-- 14. **`scripts/db-tests/rbac-enforcement.sql` compliance, verified live in
--    this checkpoint's own scratch-database run, not merely assumed.** Every
--    staff RPC calls `app.evaluate_permission` directly (an already-
--    recognized primitive in that file's own `base` regex); every customer
--    RPC calls `app.resolve_customer_account_scope` directly (also already
--    recognized, per CPL-300 design decision 10's own disclosure: "the new
--    canonical resolver every later Phase 8 capability will call, so future
--    callers are credited transitively without editing that file again") --
--    no edit to that shared file is required.
-- 15. Per `ERR-2026-004` (`docs/runtime/ERROR_LEDGER.md`): this migration
--    carries its own explicit `revoke execute on all functions in schema app
--    from public` statement before its final grants.
-- 16. **Tier C review fix (Batch 4 close), two items.** (a) **`clock_
--    timestamp()`, never `now()`, for every timestamptz column in this
--    file** -- this migration was written and merged BEFORE CPL-315's own
--    `now()`-vs-`clock_timestamp()` defect was self-found, and was never
--    revisited even though CPL-317/318/319 (all written after 315, in this
--    same batch) each proactively adopted `clock_timestamp()` throughout and
--    cite CPL-315 by name. The concrete, reachable defect this left open:
--    `app.publish_loyalty_program_rule_version` updates TWO `loyalty_
--    program_rule_versions` rows in one transaction (supersedes the prior
--    published version, publishes the new one) -- with `now()` frozen for
--    the whole transaction, both rows got a byte-identical `updated_at`, so
--    `app.list_loyalty_program_rule_versions`' own `order by updated_at
--    desc, id desc` non-deterministically ordered the superseded/published
--    pair on every republish (tie-broken on a random uuid, not real
--    insertion order). Fixed by switching every `default now()` column
--    (`loyalty_programs`/`loyalty_program_rule_versions`/`loyalty_accounts`.
--    `created_at`/`updated_at`/`enrolled_at`, `loyalty_earning_events.
--    created_at`), all three touch-row triggers, and the two explicit
--    `now()` assignments inside `app.publish_loyalty_program_rule_version`
--    (`v_effective_from`'s own fallback, `published_at`) and `app.set_
--    loyalty_account_status` (`closed_at`) to `clock_timestamp()`, mirroring
--    CPL-317/318/319's own already-applied pattern exactly. Does NOT affect
--    the financially-authoritative "which rule version is currently active"
--    resolution in `app.evaluate_customer_loyalty_earning_for_paid_invoice`
--    (governed by the `status = 'published'` partial unique index, never by
--    timestamp ordering) -- only listing/history order was ever at risk.
--    (b) **`p_expected_version IS NULL` no longer silently bypasses
--    optimistic concurrency** in `app.update_loyalty_program_status`/`app.
--    update_loyalty_program_rule_version_draft`/`app.publish_loyalty_
--    program_rule_version`/`app.set_loyalty_account_status` -- each
--    function's own early `record_version <> p_expected_version` check
--    evaluates to SQL NULL (treated as false by `if ... then raise`) when
--    `p_expected_version` is NULL, and none of the four functions' own
--    UPDATE statements repeated the version predicate, so a NULL value
--    applied the write completely unchecked. Fixed by adding `and
--    record_version = p_expected_version` to each UPDATE's own WHERE clause
--    (a NULL then matches zero rows, falling through to the same
--    `stale_version` error) -- mirrors the shape `app.decide_loyalty_point_
--    adjustment`/`app.reverse_loyalty_benefit_entitlement` (CPL-318/319)
--    already used correctly. This repository's own TS contract layer
--    already requires a positive integer for every one of these parameters,
--    so the app's own callers were never exposed -- but every one of these
--    RPCs is `grant execute ... to authenticated`, meaning a Supabase client
--    calling it directly (this repository's own stated architecture: RLS/
--    SECURITY DEFINER functions are self-defending, not merely protected by
--    the app layer) could reach it.

-- ===========================================================================
-- 1. app.loyalty_programs
-- ===========================================================================

create table app.loyalty_programs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  name text not null,
  status text not null default 'draft',
  description text,
  created_by text,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lp_status_check check (status in ('draft', 'active', 'inactive')),
  constraint lp_name_check check (length(trim(name)) > 0),
  constraint lp_tenant_name_unique unique (tenant_id, name)
);

comment on table app.loyalty_programs is
  'CPL-316: one or more named loyalty programs per tenant. Lifecycle draft -> active -> inactive -> active (app.update_loyalty_program_status). Only an active program accepts new enrollment (app.enroll_customer_loyalty_account) and awards earning (app.evaluate_customer_loyalty_earning_for_paid_invoice).';

create index lp_tenant_status_idx on app.loyalty_programs (tenant_id, status);
create index lp_tenant_updated_id_idx on app.loyalty_programs (tenant_id, updated_at desc, id desc);

create function app.touch_loyalty_program_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_programs_touch_row
  before update on app.loyalty_programs
  for each row
  execute function app.touch_loyalty_program_row();

-- ===========================================================================
-- 2. app.loyalty_program_rule_versions -- draft -> published -> superseded,
-- mirrors app.role_versions' own single-draft/single-published-per-parent
-- shape (design decision 1's own "at most one" discipline, applied here to
-- rule versions rather than active enrollment).
-- ===========================================================================

create table app.loyalty_program_rule_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  program_id uuid not null references app.loyalty_programs (id),
  version_number integer not null,
  earning_basis text not null,
  reward_type text not null,
  rate numeric not null,
  eligibility_config jsonb not null default '{}'::jsonb,
  status text not null default 'draft',
  effective_from timestamptz,
  effective_to timestamptz,
  published_by text,
  published_at timestamptz,
  record_version integer not null default 1,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint lprv_status_check check (status in ('draft', 'published', 'superseded')),
  constraint lprv_reward_type_check check (reward_type in ('points', 'cashback')),
  constraint lprv_rate_check check (rate > 0),
  constraint lprv_earning_basis_check check (length(trim(earning_basis)) > 0),
  constraint lprv_eligibility_config_check check (jsonb_typeof(eligibility_config) = 'object'),
  constraint lprv_published_shape_check check (
    (status = 'draft' and published_by is null and published_at is null and effective_from is null)
    or (status in ('published', 'superseded') and published_by is not null and published_at is not null and effective_from is not null)
  ),
  constraint lprv_superseded_shape_check check ((status = 'superseded') = (effective_to is not null)),
  constraint lprv_program_version_unique unique (program_id, version_number)
);

comment on table app.loyalty_program_rule_versions is
  'CPL-316: NEVER mutate a published version in place -- a rule change publishes a NEW version (app.publish_loyalty_program_rule_version); historical app.loyalty_earning_events retain the rule_version_id they were evaluated under forever (business rule: "Rule changes are effective-dated and do not rewrite historical earnings"). At most one draft and at most one published version per program at a time (partial unique indexes below). A superseded version keeps its own original published_by/published_at/effective_from unchanged forever -- only effective_to is set at the moment of supersession.';

create index lprv_program_idx on app.loyalty_program_rule_versions (program_id);
create index lprv_tenant_updated_id_idx on app.loyalty_program_rule_versions (tenant_id, updated_at desc, id desc);
create unique index lprv_single_draft_per_program on app.loyalty_program_rule_versions (program_id) where status = 'draft';
create unique index lprv_single_published_per_program on app.loyalty_program_rule_versions (program_id) where status = 'published';

create function app.touch_loyalty_program_rule_version_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_program_rule_versions_touch_row
  before update on app.loyalty_program_rule_versions
  for each row
  execute function app.touch_loyalty_program_rule_version_row();

-- ===========================================================================
-- 3. app.loyalty_accounts -- one per (tenant, customer_account_id,
-- program_id); at most one ACTIVE row per (tenant, customer_account_id)
-- across ALL programs (design decision 1).
-- ===========================================================================

create table app.loyalty_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  customer_account_id uuid not null references app.accounts (id),
  program_id uuid not null references app.loyalty_programs (id),
  status text not null default 'active',
  enrolled_at timestamptz not null default clock_timestamp(),
  closed_by text,
  closed_at timestamptz,
  closed_reason text,
  record_version integer not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint la_status_check check (status in ('active', 'suspended', 'closed')),
  constraint la_closed_shape_check check ((status = 'closed') = (closed_at is not null)),
  constraint la_tenant_customer_program_unique unique (tenant_id, customer_account_id, program_id)
);

comment on table app.loyalty_accounts is
  'CPL-316: a customer account''s own enrollment in a specific loyalty program. la_single_active_per_customer (below) enforces at most one ACTIVE row per (tenant, customer_account_id) at a time, tenant-wide, across every program (design decision 1) -- the mechanism that makes "the customer''s active loyalty_account" (app.evaluate_customer_loyalty_earning_for_paid_invoice''s own singular phrasing, no p_program_id parameter) well-defined and race-safe. A customer may still hold multiple HISTORICAL (suspended/closed) rows across different programs.';

create index la_tenant_customer_idx on app.loyalty_accounts (tenant_id, customer_account_id);
create index la_tenant_program_idx on app.loyalty_accounts (tenant_id, program_id);
create index la_tenant_updated_id_idx on app.loyalty_accounts (tenant_id, updated_at desc, id desc);
create unique index la_single_active_per_customer on app.loyalty_accounts (tenant_id, customer_account_id) where status = 'active';

create function app.touch_loyalty_account_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  new.record_version := old.record_version + 1;
  return new;
end;
$$;

create trigger loyalty_accounts_touch_row
  before update on app.loyalty_accounts
  for each row
  execute function app.touch_loyalty_account_row();

-- ===========================================================================
-- 4. app.loyalty_earning_events -- APPEND-ONLY. The generic, reward-type-
-- tagged earning ledger every subsequent Loyalty prompt (317 tiers, 318
-- points, 319 cashback/voucher) reads from (design decision 5).
-- ===========================================================================

create table app.loyalty_earning_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  loyalty_account_id uuid not null references app.loyalty_accounts (id),
  program_id uuid not null references app.loyalty_programs (id),
  rule_version_id uuid not null references app.loyalty_program_rule_versions (id),
  reward_type text not null,
  amount numeric not null,
  source_type text not null,
  source_id uuid,
  idempotency_key text not null,
  corrects_event_id uuid references app.loyalty_earning_events (id),
  reason text,
  created_by text,
  created_at timestamptz not null default clock_timestamp(),
  constraint lee_reward_type_check check (reward_type in ('points', 'cashback')),
  constraint lee_source_type_check check (source_type in ('finance_invoice_paid', 'reversal')),
  constraint lee_amount_check check (amount <> 0),
  constraint lee_reason_check check (corrects_event_id is null or (reason is not null and length(trim(reason)) > 0)),
  constraint lee_tenant_idempotency_unique unique (tenant_id, idempotency_key)
);

comment on table app.loyalty_earning_events is
  'CPL-316: append-only. No UPDATE/DELETE grant to any non-service_role caller anywhere in this migration -- a correction is always a NEW, linked row (corrects_event_id), mirroring app.inventory_movements.corrects_movement_id exactly (design decision 12). reward_type is a denormalized, frozen-forever copy of the rule version''s own reward_type at evaluation time -- rule_version_id alone already pins the full historical context (business rule: rule changes never rewrite historical earnings). No currency column (design decision 6) -- cashback amounts are implicitly denominated in their own source app.finance_ar_open_items.currency, reachable via source_id.';

create index lee_tenant_account_created_idx on app.loyalty_earning_events (tenant_id, loyalty_account_id, created_at desc);
create index lee_tenant_created_id_idx on app.loyalty_earning_events (tenant_id, created_at desc, id desc);
create index lee_source_idx on app.loyalty_earning_events (source_type, source_id);
create index lee_corrects_event_idx on app.loyalty_earning_events (corrects_event_id);

-- ===========================================================================
-- 5. app.create_loyalty_program -- staff, LYL:Create
-- ===========================================================================

create function app.create_loyalty_program(
  p_tenant_id uuid,
  p_name text,
  p_description text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_programs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'invalid_name: a non-empty program name is required' using errcode = 'check_violation';
  end if;

  begin
    insert into app.loyalty_programs (tenant_id, name, description, created_by)
    values (p_tenant_id, trim(p_name), p_description, p_actor_label)
    returning * into v_program;
  exception
    when unique_violation then
      raise exception 'loyalty_program_name_conflict: tenant % already has a program named %', p_tenant_id, trim(p_name) using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_loyalty_program',
    'app.loyalty_programs', v_program.id, 'success', null, null, to_jsonb(v_program)
  );

  return v_program;
end;
$$;

-- ===========================================================================
-- 6. app.update_loyalty_program_status -- staff, LYL:Edit
-- ===========================================================================

create function app.update_loyalty_program_status(
  p_tenant_id uuid,
  p_program_id uuid,
  p_expected_version integer,
  p_new_status text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_programs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
  v_updated app.loyalty_programs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_new_status not in ('draft', 'active', 'inactive') then
    raise exception 'invalid_status: % is not a recognized loyalty program status', p_new_status using errcode = 'check_violation';
  end if;

  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_program_not_found: %', p_program_id using errcode = 'no_data_found';
  end if;

  if v_program.record_version <> p_expected_version then
    raise exception 'stale_version: loyalty program % expected version % but found %', p_program_id, p_expected_version, v_program.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_new_status = v_program.status then
    return v_program;
  end if;

  if not (
    (v_program.status = 'draft' and p_new_status = 'active')
    or (v_program.status = 'active' and p_new_status = 'inactive')
    or (v_program.status = 'inactive' and p_new_status = 'active')
  ) then
    raise exception 'invalid_transition: % -> % is not a canonical loyalty program transition', v_program.status, p_new_status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_programs set status = p_new_status where id = p_program_id and record_version = p_expected_version returning * into v_updated;
  if not found then
    raise exception 'stale_version: loyalty program % was concurrently modified (expected version %)', p_program_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_loyalty_program_status',
    'app.loyalty_programs', v_updated.id, 'success', null,
    jsonb_build_object('status', v_program.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 7. app.get_loyalty_program / app.list_loyalty_programs -- staff, LYL:View
-- ===========================================================================

create function app.get_loyalty_program(p_tenant_id uuid, p_program_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_programs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_not_found: %', p_program_id using errcode = 'no_data_found';
  end if;

  return v_program;
end;
$$;

create function app.list_loyalty_programs(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_programs
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
  select p.* from app.loyalty_programs p
  where p.tenant_id = p_tenant_id
    and (p_status is null or p.status = p_status)
    and (p_cursor_id is null or (p.updated_at, p.id) < (p_cursor_updated_at, p_cursor_id))
  order by p.updated_at desc, p.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 8. app.create_loyalty_program_rule_version -- staff, LYL:Create
-- ===========================================================================

create function app.create_loyalty_program_rule_version(
  p_tenant_id uuid,
  p_program_id uuid,
  p_earning_basis text,
  p_reward_type text,
  p_rate numeric,
  p_eligibility_config jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_program_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
  v_next_version integer;
  v_version app.loyalty_program_rule_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reward_type not in ('points', 'cashback') then
    raise exception 'invalid_reward_type: % must be points or cashback', p_reward_type using errcode = 'check_violation';
  end if;
  if p_earning_basis is null or length(trim(p_earning_basis)) = 0 then
    raise exception 'invalid_earning_basis: a non-empty earning basis is required' using errcode = 'check_violation';
  end if;
  if p_rate is null or p_rate <= 0 then
    raise exception 'invalid_rate: rate must be a positive number, got %', p_rate using errcode = 'check_violation';
  end if;
  if p_eligibility_config is not null and jsonb_typeof(p_eligibility_config) <> 'object' then
    raise exception 'invalid_eligibility_config: eligibility_config must be a JSON object' using errcode = 'check_violation';
  end if;

  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_not_found: %', p_program_id using errcode = 'no_data_found';
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version from app.loyalty_program_rule_versions where program_id = p_program_id;

  begin
    insert into app.loyalty_program_rule_versions (
      tenant_id, program_id, version_number, earning_basis, reward_type, rate, eligibility_config, created_by
    ) values (
      p_tenant_id, p_program_id, v_next_version, trim(p_earning_basis), p_reward_type, p_rate, coalesce(p_eligibility_config, '{}'::jsonb), p_actor_label
    )
    returning * into v_version;
  exception
    when unique_violation then
      raise exception 'draft_already_exists: program % already has an open draft rule version', p_program_id using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'create_loyalty_program_rule_version',
    'app.loyalty_program_rule_versions', v_version.id, 'success', null, null, to_jsonb(v_version)
  );

  return v_version;
end;
$$;

comment on function app.create_loyalty_program_rule_version is
  'CPL-316: at most one draft per program at a time (lprv_single_draft_per_program) -- a real exception-handler-backed check, not a pre-check-only pattern (a concurrent double-draft-create race converges on a clean draft_already_exists, never a raw constraint-violation leak).';

-- ===========================================================================
-- 9. app.update_loyalty_program_rule_version_draft -- staff, LYL:Edit,
-- draft-only
-- ===========================================================================

create function app.update_loyalty_program_rule_version_draft(
  p_tenant_id uuid,
  p_rule_version_id uuid,
  p_expected_version integer,
  p_earning_basis text,
  p_reward_type text,
  p_rate numeric,
  p_eligibility_config jsonb,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_program_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.loyalty_program_rule_versions;
  v_updated app.loyalty_program_rule_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_reward_type not in ('points', 'cashback') then
    raise exception 'invalid_reward_type: % must be points or cashback', p_reward_type using errcode = 'check_violation';
  end if;
  if p_earning_basis is null or length(trim(p_earning_basis)) = 0 then
    raise exception 'invalid_earning_basis: a non-empty earning basis is required' using errcode = 'check_violation';
  end if;
  if p_rate is null or p_rate <= 0 then
    raise exception 'invalid_rate: rate must be a positive number, got %', p_rate using errcode = 'check_violation';
  end if;
  if p_eligibility_config is not null and jsonb_typeof(p_eligibility_config) <> 'object' then
    raise exception 'invalid_eligibility_config: eligibility_config must be a JSON object' using errcode = 'check_violation';
  end if;

  select * into v_version from app.loyalty_program_rule_versions where id = p_rule_version_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_program_rule_version_not_found: %', p_rule_version_id using errcode = 'no_data_found';
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: rule version % expected version % but found %', p_rule_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: rule version % is % -- only a draft may be edited', p_rule_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  update app.loyalty_program_rule_versions
  set earning_basis = trim(p_earning_basis), reward_type = p_reward_type, rate = p_rate, eligibility_config = coalesce(p_eligibility_config, '{}'::jsonb)
  where id = p_rule_version_id and record_version = p_expected_version
  returning * into v_updated;
  if not found then
    raise exception 'stale_version: rule version % was concurrently modified (expected version %)', p_rule_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'update_loyalty_program_rule_version_draft',
    'app.loyalty_program_rule_versions', v_updated.id, 'success', null, null, to_jsonb(v_updated)
  );

  return v_updated;
end;
$$;

-- ===========================================================================
-- 10. app.publish_loyalty_program_rule_version -- staff, LYL:Configure
-- (design decision 4's elevated action). Supersedes the program's prior
-- published version, if any, in the SAME transaction. NEVER mutates a
-- published version in place (business rule).
-- ===========================================================================

create function app.publish_loyalty_program_rule_version(
  p_tenant_id uuid,
  p_rule_version_id uuid,
  p_expected_version integer,
  p_effective_from timestamptz,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_program_rule_versions
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.loyalty_program_rule_versions;
  v_prior_published app.loyalty_program_rule_versions;
  v_effective_from timestamptz;
  v_published app.loyalty_program_rule_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.loyalty_program_rule_versions where id = p_rule_version_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_program_rule_version_not_found: %', p_rule_version_id using errcode = 'no_data_found';
  end if;

  if v_version.record_version <> p_expected_version then
    raise exception 'stale_version: rule version % expected version % but found %', p_rule_version_id, p_expected_version, v_version.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_version.status <> 'draft' then
    raise exception 'invalid_transition: rule version % is % -- only a draft may be published', p_rule_version_id, v_version.status
      using errcode = 'check_violation';
  end if;

  v_effective_from := coalesce(p_effective_from, clock_timestamp());

  -- Lock and supersede the program's own currently published version, if
  -- any -- its own published_by/published_at/effective_from are NEVER
  -- touched, only status/effective_to (business rule: never mutate a
  -- published version's own recorded facts).
  select * into v_prior_published from app.loyalty_program_rule_versions
    where program_id = v_version.program_id and status = 'published' for update;
  if found then
    update app.loyalty_program_rule_versions
      set status = 'superseded', effective_to = v_effective_from
      where id = v_prior_published.id;
  end if;

  update app.loyalty_program_rule_versions
    set status = 'published', published_by = p_actor_label, published_at = clock_timestamp(), effective_from = v_effective_from
    where id = p_rule_version_id and record_version = p_expected_version
    returning * into v_published;
  if not found then
    raise exception 'stale_version: rule version % was concurrently modified (expected version %)', p_rule_version_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;

  perform app.capture_audit_event(
    v_published.tenant_id, p_actor_auth_user_id, p_actor_label, 'publish_loyalty_program_rule_version',
    'app.loyalty_program_rule_versions', v_published.id, 'success', null,
    case when v_prior_published.id is not null then jsonb_build_object('supersedes_rule_version_id', v_prior_published.id) else null end,
    to_jsonb(v_published)
  );

  return v_published;
end;
$$;

-- ===========================================================================
-- 11. app.get_loyalty_program_rule_version / app.list_loyalty_program_rule_
-- versions -- staff, LYL:View
-- ===========================================================================

create function app.get_loyalty_program_rule_version(p_tenant_id uuid, p_rule_version_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_program_rule_versions
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_version app.loyalty_program_rule_versions;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_version from app.loyalty_program_rule_versions where id = p_rule_version_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_rule_version_not_found: %', p_rule_version_id using errcode = 'no_data_found';
  end if;

  return v_version;
end;
$$;

create function app.list_loyalty_program_rule_versions(
  p_tenant_id uuid,
  p_program_id uuid,
  p_actor_auth_user_id uuid,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_program_rule_versions
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
  select r.* from app.loyalty_program_rule_versions r
  where r.tenant_id = p_tenant_id
    and (p_program_id is null or r.program_id = p_program_id)
    and (p_status is null or r.status = p_status)
    and (p_cursor_id is null or (r.updated_at, r.id) < (p_cursor_updated_at, p_cursor_id))
  order by r.updated_at desc, r.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 12. app.enroll_customer_loyalty_account -- staff, LYL:Create
-- ===========================================================================

create function app.enroll_customer_loyalty_account(
  p_tenant_id uuid,
  p_customer_account_id uuid,
  p_program_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_accounts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
  v_customer app.accounts;
  v_existing app.loyalty_accounts;
  v_account app.loyalty_accounts;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent short-circuit (natural key), AFTER the authority check
  -- (mandatory pattern, design decision 11).
  select * into v_existing from app.loyalty_accounts
    where tenant_id = p_tenant_id and customer_account_id = p_customer_account_id and program_id = p_program_id;
  if found then
    return v_existing;
  end if;

  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_not_found: %', p_program_id using errcode = 'no_data_found';
  end if;
  if v_program.status <> 'active' then
    raise exception 'loyalty_program_not_active: program % is % -- only an active program accepts enrollment', p_program_id, v_program.status
      using errcode = 'check_violation';
  end if;

  select * into v_customer from app.accounts where id = p_customer_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'customer_account_not_found: % is not an account of tenant %', p_customer_account_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  if exists (
    select 1 from app.loyalty_accounts
    where tenant_id = p_tenant_id and customer_account_id = p_customer_account_id and status = 'active'
  ) then
    raise exception 'customer_already_has_active_enrollment: account % already holds an active loyalty enrollment in a different program', p_customer_account_id
      using errcode = 'check_violation';
  end if;

  begin
    insert into app.loyalty_accounts (tenant_id, customer_account_id, program_id)
    values (p_tenant_id, p_customer_account_id, p_program_id)
    returning * into v_account;
  exception
    when unique_violation then
      select * into v_account from app.loyalty_accounts
        where tenant_id = p_tenant_id and customer_account_id = p_customer_account_id and program_id = p_program_id;
      if found then
        return v_account;
      end if;
      raise exception 'customer_already_has_active_enrollment: account % already holds an active loyalty enrollment in a different program', p_customer_account_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'enroll_customer_loyalty_account',
    'app.loyalty_accounts', v_account.id, 'success', null, null, to_jsonb(v_account)
  );

  return v_account;
end;
$$;

-- ===========================================================================
-- 13. app.set_loyalty_account_status -- staff, LYL:Edit
-- ===========================================================================

create function app.set_loyalty_account_status(
  p_tenant_id uuid,
  p_account_id uuid,
  p_expected_version integer,
  p_new_status text,
  p_reason text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_accounts
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
  v_updated app.loyalty_accounts;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_new_status not in ('active', 'suspended', 'closed') then
    raise exception 'invalid_status: % is not a status this function may set', p_new_status using errcode = 'check_violation';
  end if;
  if p_new_status in ('suspended', 'closed') and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'reason_required: a non-empty reason is required to % a loyalty account', p_new_status using errcode = 'not_null_violation';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_account_id and tenant_id = p_tenant_id for update;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  if v_account.record_version <> p_expected_version then
    raise exception 'stale_version: loyalty account % expected version % but found %', p_account_id, p_expected_version, v_account.record_version
      using errcode = 'serialization_failure';
  end if;

  if p_new_status = v_account.status then
    return v_account;
  end if;

  if v_account.status = 'closed' then
    raise exception 'invalid_transition: loyalty account % is closed, no further transition is allowed', p_account_id using errcode = 'check_violation';
  end if;
  if not (
    (v_account.status = 'active' and p_new_status in ('suspended', 'closed'))
    or (v_account.status = 'suspended' and p_new_status in ('active', 'closed'))
  ) then
    raise exception 'invalid_transition: % -> % is not a canonical loyalty account transition', v_account.status, p_new_status
      using errcode = 'check_violation';
  end if;

  begin
    update app.loyalty_accounts
    set status = p_new_status,
        closed_by = case when p_new_status = 'closed' then p_actor_label else closed_by end,
        closed_at = case when p_new_status = 'closed' then clock_timestamp() else closed_at end,
        closed_reason = case when p_new_status = 'closed' then p_reason else closed_reason end
    where id = p_account_id and record_version = p_expected_version
    returning * into v_updated;
  if not found then
    raise exception 'stale_version: loyalty account % was concurrently modified (expected version %)', p_account_id, p_expected_version
      using errcode = 'serialization_failure';
  end if;
  exception
    when unique_violation then
      raise exception 'customer_already_has_active_enrollment: cannot reactivate -- account % already holds a different active enrollment', v_account.customer_account_id
        using errcode = 'check_violation';
  end;

  perform app.capture_audit_event(
    v_updated.tenant_id, p_actor_auth_user_id, p_actor_label, 'set_loyalty_account_status',
    'app.loyalty_accounts', v_updated.id, 'success', p_reason,
    jsonb_build_object('status', v_account.status), jsonb_build_object('status', v_updated.status)
  );

  return v_updated;
end;
$$;

comment on function app.set_loyalty_account_status is
  'CPL-316: active <-> suspended <-> closed(terminal). Reactivating (-> active) is rejected if it would collide with la_single_active_per_customer (a real exception-handler-backed check, not a pre-check-only pattern) -- the customer already holds a different active enrollment.';

-- ===========================================================================
-- 14. app.get_loyalty_account / app.list_loyalty_accounts -- staff, LYL:View
-- ===========================================================================

create function app.get_loyalty_account(p_tenant_id uuid, p_account_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_accounts
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_account app.loyalty_accounts;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_account from app.loyalty_accounts where id = p_account_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_account_not_found: %', p_account_id using errcode = 'no_data_found';
  end if;

  return v_account;
end;
$$;

create function app.list_loyalty_accounts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_program_id uuid default null,
  p_customer_account_id uuid default null,
  p_status text default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_accounts
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
  select a.* from app.loyalty_accounts a
  where a.tenant_id = p_tenant_id
    and (p_program_id is null or a.program_id = p_program_id)
    and (p_customer_account_id is null or a.customer_account_id = p_customer_account_id)
    and (p_status is null or a.status = p_status)
    and (p_cursor_id is null or (a.updated_at, a.id) < (p_cursor_updated_at, p_cursor_id))
  order by a.updated_at desc, a.id desc
  limit v_limit;
end;
$$;

-- ===========================================================================
-- 15. app.evaluate_customer_loyalty_earning_for_paid_invoice -- staff/system,
-- LYL:Edit. The ONE ledger-posting entry point (design decisions 1, 7, 8,
-- 9, 11).
-- ===========================================================================

create function app.evaluate_customer_loyalty_earning_for_paid_invoice(
  p_tenant_id uuid,
  p_ar_open_item_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_earning_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_idempotency_key text;
  v_existing app.loyalty_earning_events;
  v_ar app.finance_ar_open_items;
  v_account app.loyalty_accounts;
  v_program app.loyalty_programs;
  v_rule app.loyalty_program_rule_versions;
  v_min_amount numeric;
  v_amount numeric;
  v_event app.loyalty_earning_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Deterministic, source-derived idempotency key -- never client-supplied,
  -- never Date.now()-based. Idempotent short-circuit AFTER the authority
  -- check (mandatory pattern, design decision 11): a retried call for the
  -- SAME paid invoice is a safe no-op that returns the ORIGINAL event
  -- unchanged, never re-validates the AR item's CURRENT state and never
  -- recomputes the amount under a since-superseded rule version.
  v_idempotency_key := 'ar-open-item:' || p_ar_open_item_id::text;
  select * into v_existing from app.loyalty_earning_events where tenant_id = p_tenant_id and idempotency_key = v_idempotency_key;
  if found then
    return v_existing;
  end if;

  select * into v_ar from app.finance_ar_open_items where id = p_ar_open_item_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'ar_open_item_not_found: % is not an AR open item of tenant %', p_ar_open_item_id, p_tenant_id using errcode = 'no_data_found';
  end if;
  if v_ar.status <> 'paid' then
    raise exception 'ar_open_item_not_paid: % is % -- only a fully paid open item is eligible for loyalty earning', p_ar_open_item_id, v_ar.status
      using errcode = 'check_violation';
  end if;
  if v_ar.is_held then
    raise exception 'ar_open_item_held: % is currently held -- a held item is not eligible for loyalty earning', p_ar_open_item_id
      using errcode = 'check_violation';
  end if;

  select * into v_account from app.loyalty_accounts
    where tenant_id = p_tenant_id and customer_account_id = v_ar.customer_account_id and status = 'active';
  if not found then
    raise exception 'loyalty_account_not_active: customer account % has no active loyalty enrollment in tenant %', v_ar.customer_account_id, p_tenant_id
      using errcode = 'no_data_found';
  end if;

  select * into v_program from app.loyalty_programs where id = v_account.program_id;
  if not found or v_program.status <> 'active' then
    raise exception 'loyalty_program_not_active: program % is not currently active', v_account.program_id using errcode = 'check_violation';
  end if;

  select * into v_rule from app.loyalty_program_rule_versions
    where program_id = v_account.program_id and status = 'published';
  if not found then
    raise exception 'no_published_rule_version: program % has no currently published rule version', v_account.program_id
      using errcode = 'no_data_found';
  end if;

  if v_rule.earning_basis <> 'per_paid_invoice_amount' then
    raise exception 'unsupported_earning_basis: % is not an earning basis this evaluator can compute', v_rule.earning_basis
      using errcode = 'check_violation';
  end if;

  v_min_amount := nullif(v_rule.eligibility_config ->> 'min_invoice_amount', '')::numeric;
  if v_min_amount is not null and v_ar.original_amount < v_min_amount then
    raise exception 'ineligible_amount_below_minimum: invoice amount % is below the program''s own configured minimum %', v_ar.original_amount, v_min_amount
      using errcode = 'check_violation';
  end if;

  v_amount := case
    when v_rule.reward_type = 'cashback' then round(v_ar.original_amount * v_rule.rate, 2)
    else round(v_ar.original_amount * v_rule.rate)
  end;
  if v_amount is null or v_amount <= 0 then
    raise exception 'computed_amount_not_positive: computed reward amount % is not positive', v_amount using errcode = 'check_violation';
  end if;

  begin
    insert into app.loyalty_earning_events (
      tenant_id, loyalty_account_id, program_id, rule_version_id, reward_type, amount, source_type, source_id, idempotency_key, created_by
    ) values (
      p_tenant_id, v_account.id, v_account.program_id, v_rule.id, v_rule.reward_type, v_amount, 'finance_invoice_paid', p_ar_open_item_id, v_idempotency_key, p_actor_label
    )
    returning * into v_event;
  exception
    when unique_violation then
      select * into v_event from app.loyalty_earning_events where tenant_id = p_tenant_id and idempotency_key = v_idempotency_key;
      if not found then
        raise;
      end if;
      return v_event;
  end;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'evaluate_customer_loyalty_earning_for_paid_invoice',
    'app.loyalty_earning_events', v_event.id, 'success', null, null,
    jsonb_build_object('ar_open_item_id', p_ar_open_item_id, 'loyalty_account_id', v_account.id, 'rule_version_id', v_rule.id, 'reward_type', v_rule.reward_type, 'amount', v_amount)
  );

  return v_event;
end;
$$;

comment on function app.evaluate_customer_loyalty_earning_for_paid_invoice is
  'CPL-316: idempotent on (tenant_id, ''ar-open-item:'' || ar_open_item_id) -- calling this twice for the same paid invoice is a safe no-op, never a duplicate award (mandatory pattern). Resolves the customer''s SINGLE active loyalty_account (design decision 1) and the program''s CURRENTLY PUBLISHED rule version (never a superseded or draft one). Rejects an unpaid or held AR open item, an inactive program, a missing published rule version, an unsupported earning_basis, and a below-minimum amount. On-demand/staff-triggered only in this checkpoint -- no automatic job/trigger wiring (design decision 9, ISS-2026-126).';

-- ===========================================================================
-- 16. app.reverse_loyalty_earning_event -- staff, LYL:Configure (design
-- decision 4's elevated action, a governed ledger correction).
-- ===========================================================================

create function app.reverse_loyalty_earning_event(
  p_tenant_id uuid,
  p_event_id uuid,
  p_reason text,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_earning_events
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_original app.loyalty_earning_events;
  v_existing app.loyalty_earning_events;
  v_reversal app.loyalty_earning_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'invalid_idempotency_key: an idempotency key is required to reverse a loyalty earning event' using errcode = 'check_violation';
  end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason_required: a non-empty reason is required to reverse a loyalty earning event' using errcode = 'not_null_violation';
  end if;

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern).
  select * into v_existing from app.loyalty_earning_events where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  select * into v_original from app.loyalty_earning_events where id = p_event_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_earning_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;
  if v_original.corrects_event_id is not null then
    raise exception 'invalid_reversal: a reversal event may not itself be reversed' using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.loyalty_earning_events where corrects_event_id = p_event_id) then
    raise exception 'already_reversed: loyalty earning event % has already been reversed', p_event_id using errcode = 'check_violation';
  end if;

  begin
    insert into app.loyalty_earning_events (
      tenant_id, loyalty_account_id, program_id, rule_version_id, reward_type, amount, source_type, source_id, idempotency_key, corrects_event_id, reason, created_by
    ) values (
      v_original.tenant_id, v_original.loyalty_account_id, v_original.program_id, v_original.rule_version_id, v_original.reward_type,
      -v_original.amount, 'reversal', v_original.id, p_idempotency_key, v_original.id, p_reason, p_actor_label
    )
    returning * into v_reversal;
  exception
    when unique_violation then
      select * into v_reversal from app.loyalty_earning_events where tenant_id = p_tenant_id and idempotency_key = p_idempotency_key;
      if not found then
        raise;
      end if;
      return v_reversal;
  end;

  perform app.capture_audit_event(
    v_original.tenant_id, p_actor_auth_user_id, p_actor_label, 'reverse_loyalty_earning_event',
    'app.loyalty_earning_events', v_reversal.id, 'success', p_reason, null,
    jsonb_build_object('corrects_event_id', v_original.id, 'amount', -v_original.amount)
  );

  return v_reversal;
end;
$$;

comment on function app.reverse_loyalty_earning_event is
  'CPL-316: NEVER deletes or edits the original event -- inserts a NEW, linked row (corrects_event_id), exact negation of the original amount, mirroring app.reverse_inventory_movement exactly (design decisions 10, 12). At most one reversal per original event; a reversal event may not itself be reversed. Idempotent on (tenant_id, idempotency_key) -- a real exception-handler-backed check, not a pre-check-only pattern.';

-- ===========================================================================
-- 17. app.get_loyalty_earning_event / app.list_loyalty_earning_events --
-- staff, LYL:View (full internal projection)
-- ===========================================================================

create function app.get_loyalty_earning_event(p_tenant_id uuid, p_event_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_earning_events
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_event app.loyalty_earning_events;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_event from app.loyalty_earning_events where id = p_event_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_earning_event_not_found: %', p_event_id using errcode = 'no_data_found';
  end if;

  return v_event;
end;
$$;

create function app.list_loyalty_earning_events(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_loyalty_account_id uuid default null,
  p_program_id uuid default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns setof app.loyalty_earning_events
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
  select e.* from app.loyalty_earning_events e
  where e.tenant_id = p_tenant_id
    and (p_loyalty_account_id is null or e.loyalty_account_id = p_loyalty_account_id)
    and (p_program_id is null or e.program_id = p_program_id)
    and (p_cursor_id is null or (e.created_at, e.id) < (p_cursor_created_at, p_cursor_id))
  order by e.created_at desc, e.id desc
  limit v_limit;
end;
$$;

comment on function app.list_loyalty_earning_events is
  'CPL-316: keyset-paginated on (created_at desc, id desc) -- app.loyalty_earning_events has no updated_at column (append-only, immutable rows), so created_at is the equivalent stable keyset field (mandatory pattern''s own "or equivalent stable keyset" allowance).';

-- ===========================================================================
-- 18. app.list_customer_portal_loyalty_accounts -- customer-facing (Layer 4,
-- ADR-0024 Part A). Deny-by-default: out-of-scope or zero-enrollment both
-- return an empty result, never an error.
-- ===========================================================================

create function app.list_customer_portal_loyalty_accounts(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_account_id uuid default null,
  p_cursor_updated_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  customer_account_id uuid,
  program_id uuid,
  program_name text,
  status text,
  enrolled_at timestamptz,
  record_version integer,
  updated_at timestamptz
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

  if p_cursor_id is not null and p_cursor_updated_at is null then
    raise exception 'invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_customer_account_id is not null and not (p_customer_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select la.id, la.customer_account_id, la.program_id, p.name, la.status, la.enrolled_at, la.record_version, la.updated_at
  from app.loyalty_accounts la
  join app.loyalty_programs p on p.id = la.program_id
  where la.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and (p_customer_account_id is null or la.customer_account_id = p_customer_account_id)
    and (p_cursor_id is null or (la.updated_at, la.id) < (p_cursor_updated_at, p_cursor_id))
  order by la.updated_at desc, la.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_accounts is
  'CPL-316: customer-safe projection of a customer''s own loyalty enrollments (any status -- a closed enrollment stays visible in its own account''s history). Never exposes any other account''s row. Deny-by-default: an out-of-scope p_customer_account_id or an empty resolved scope both return zero rows, never an error.';

-- ===========================================================================
-- 19. app.list_customer_portal_loyalty_earning_events -- customer-facing
-- (Layer 4). Customer-safe explanation: cites the rule version''s own
-- human-readable earning_basis/rate, never eligibility_config verbatim.
-- ===========================================================================

create function app.list_customer_portal_loyalty_earning_events(
  p_tenant_id uuid,
  p_actor_auth_user_id uuid,
  p_customer_account_id uuid default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  program_name text,
  reward_type text,
  amount numeric,
  earning_basis text,
  rate numeric,
  source_type text,
  reason text,
  corrects_event_id uuid,
  created_at timestamptz
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

  if p_cursor_id is not null and p_cursor_created_at is null then
    raise exception 'invalid_cursor: p_cursor_created_at is required when p_cursor_id is supplied' using errcode = 'invalid_parameter_value';
  end if;

  v_scope := app.resolve_customer_account_scope(p_actor_auth_user_id, p_tenant_id);
  if array_length(v_scope, 1) is null then
    return;
  end if;
  if p_customer_account_id is not null and not (p_customer_account_id = any (v_scope)) then
    return;
  end if;

  v_limit := least(greatest(coalesce(p_limit, 50), 1), 200);

  return query
  select e.id, p.name, e.reward_type, e.amount, r.earning_basis, r.rate, e.source_type, e.reason, e.corrects_event_id, e.created_at
  from app.loyalty_earning_events e
  join app.loyalty_accounts la on la.id = e.loyalty_account_id
  join app.loyalty_programs p on p.id = e.program_id
  join app.loyalty_program_rule_versions r on r.id = e.rule_version_id
  where e.tenant_id = p_tenant_id
    and la.customer_account_id = any (v_scope)
    and (p_customer_account_id is null or la.customer_account_id = p_customer_account_id)
    and (p_cursor_id is null or (e.created_at, e.id) < (p_cursor_created_at, p_cursor_id))
  order by e.created_at desc, e.id desc
  limit v_limit;
end;
$$;

comment on function app.list_customer_portal_loyalty_earning_events is
  'CPL-316: customer-safe earning history projection. Cites the evaluated rule version''s own human-readable earning_basis (e.g. per_paid_invoice_amount) and rate directly -- NEVER the rule version''s internal eligibility_config jsonb verbatim (source prompt: "cite the rule version''s own human-readable basis, never internal config JSON verbatim"). Never exposes loyalty_account_id/program_id/rule_version_id/source_id (internal linkage). Deny-by-default, keyset-paginated on (created_at desc, id desc) (no updated_at column -- append-only).';

-- ===========================================================================
-- 20. RLS -- enable, grant service_role only (design decision 13).
-- ===========================================================================

alter table app.loyalty_programs enable row level security;
alter table app.loyalty_program_rule_versions enable row level security;
alter table app.loyalty_accounts enable row level security;
alter table app.loyalty_earning_events enable row level security;

grant select, insert, update, delete on app.loyalty_programs, app.loyalty_program_rule_versions, app.loyalty_accounts to service_role;
grant select, insert on app.loyalty_earning_events to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.create_loyalty_program(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.update_loyalty_program_status(uuid, uuid, integer, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_program(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_programs(uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.create_loyalty_program_rule_version(uuid, uuid, text, text, numeric, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.update_loyalty_program_rule_version_draft(uuid, uuid, integer, text, text, numeric, jsonb, uuid, text) to authenticated, service_role;
grant execute on function app.publish_loyalty_program_rule_version(uuid, uuid, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_program_rule_version(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_program_rule_versions(uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.enroll_customer_loyalty_account(uuid, uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.set_loyalty_account_status(uuid, uuid, integer, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_account(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_accounts(uuid, uuid, uuid, uuid, text, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.evaluate_customer_loyalty_earning_for_paid_invoice(uuid, uuid, uuid, text) to authenticated, service_role;
grant execute on function app.reverse_loyalty_earning_event(uuid, uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_earning_event(uuid, uuid, uuid) to authenticated, service_role;
grant execute on function app.list_loyalty_earning_events(uuid, uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_accounts(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
grant execute on function app.list_customer_portal_loyalty_earning_events(uuid, uuid, uuid, timestamptz, uuid, integer) to authenticated, service_role;
