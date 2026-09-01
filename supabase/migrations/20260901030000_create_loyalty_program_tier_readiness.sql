-- Track B, ISS-2026-127 item 2 (docs/runtime/KNOWN_ISSUES.md).
--
-- Read in full before writing this file: supabase/migrations/20260801190000_
-- create_customer_portal_loyalty_membership_tier.sql (CPL-317, owns
-- app.recalculate_customer_loyalty_tier and app.loyalty_tier_definitions/
-- app.loyalty_accounts/app.loyalty_account_tier_movements -- all read-only
-- here, never written), and 20260831230000_add_loyalty_earning_tier_and_
-- points_posting_sweeps.sql (owns app.run_loyalty_tier_recalculation_sweep,
-- the nightly sweep this migration gives an admin-facing early-warning
-- surface for). Both re-read LIVE via pg_get_functiondef before this file was
-- drafted, not trusted from either migration's own on-disk text, per this
-- repository's own documented near-miss discipline (a later migration can
-- change a function's body without this one's author knowing).
--
-- ===========================================================================
-- The gap this closes (re-derived live, not assumed from the issue text)
-- ===========================================================================
--
-- app.recalculate_customer_loyalty_tier raises a real, loud
-- no_eligible_tier_definition (or unsupported_threshold_dimension) when a
-- programme's own published tier ladder cannot resolve an account's current
-- computed amount to any tier -- correct, deliberate, disclosed behavior
-- (ISS-2026-127 item 2), never weakened here. What changed underneath it
-- is app.run_loyalty_tier_recalculation_sweep (2026-08-31): the sweep now
-- catches that raise PER ACCOUNT so one misconfigured account can never
-- abort a whole tenant's run, and counts it as a skip on the job row's own
-- payload (skipped_count/skips, capped at 20 reasons). That skip payload has
-- no admin-facing reader anywhere in this repository (grep-confirmed: no
-- app/ or server/ file references skipped_count or the sweep job's own
-- skips array) -- a tenant admin who publishes a tier ladder with no base
-- (threshold_value = 0) rung, or a published tier using an unsupported
-- threshold_dimension, gets no warning at all; the sweep simply, silently,
-- correctly does nothing for that account, forever, every night.
--
-- This migration adds exactly one new, additive, advisory, read-only
-- surface: a per-(tenant, program) readiness snapshot an admin screen can
-- show BEFORE the sweep ever runs. It never gates publish, never
-- auto-creates a base tier, never changes recalculation's own raise
-- behavior, and never touches app.loyalty_account_tier_movements' schema.
--
-- ===========================================================================
-- Design decisions (disclosed)
-- ===========================================================================
--
-- 1. **has_base_tier checks threshold_value = 0 on a PUBLISHED tier only**,
--    mirroring app.recalculate_customer_loyalty_tier's own eligible-tier
--    resolution, which only ever considers status = 'published' rows
--    (design decision 8 of the migration that owns it). A base tier is
--    reported even when its own threshold_dimension is unsupported (the
--    "Bad Dimension Program" fixture's own "Weird" tier: threshold_value=0,
--    threshold_dimension='transaction_count_lifetime') -- has_base_tier and
--    unsupported_dimension_tier_count are deliberately independent signals,
--    never folded into one boolean, so a caller can tell "no base rung
--    published" apart from "a base rung exists but uses a dimension this
--    checkpoint cannot compute."
-- 2. **untiered_active_account_count is the literal, direct count of active
--    enrolments with ZERO rows in app.loyalty_account_tier_movements** --
--    never a re-derivation of "would recalculation currently raise for
--    this account", which the live function body above already proves
--    would require re-implementing its own eligibility arithmetic here (a
--    second, drifting copy of business logic this migration must not
--    create). The literal count already captures the two live failure
--    modes disclosed in ISS-2026-127 item 2 and the case this migration
--    adds: (a) no published base tier at all (every enrolled account stays
--    untiered forever); (b) a published base tier exists, but a newly
--    enrolled account's own current year-to-date earning sum is negative
--    (an early reversal/chargeback posted before any genuine earning) --
--    threshold_value <= computed_amount fails even for a threshold_value=0
--    base tier when computed_amount is negative, so that account is
--    ALSO untiered despite a technically valid ladder. A readiness surface
--    that only checked "has_base_tier" would silently miss (b) entirely;
--    this field cannot, because it counts the real outcome (no tier ever
--    assigned), not merely one of its two live causes.
-- 3. **RBAC: LYL:View, the same tenant-internal staff authority every other
--    read in this domain requires** (app.get_loyalty_tier_definition,
--    app.get_loyalty_account_tier_state) -- this is a read of aggregate
--    tenant-owned configuration health, not per-record customer data, so it
--    carries no additional record-scope check beyond the tenant boundary
--    LYL:View already enforces. Authority is checked BEFORE the programme
--    is looked up (mirrors app.get_loyalty_tier_definition's own ordering)
--    so a tenant-B caller passing a tenant-A program id under p_tenant_id =
--    tenant B gets the identical loyalty_program_not_found a genuinely
--    nonexistent id would -- existence never leaks across the tenant
--    boundary.
-- 4. **Read-only, STABLE, zero writes, never calls app.capture_audit_event**
--    -- a query, not a mutation, exactly like every other app.get_*
--    readiness/state function in this codebase (app.get_wms_outbound_
--    readiness, app.get_wms_inbound_readiness, app.get_loyalty_account_
--    tier_state).
-- 5. **Advisory only.** Nothing in this migration changes what app.
--    recalculate_customer_loyalty_tier or app.run_loyalty_tier_
--    recalculation_sweep do; no publish-time gate is added to app.
--    publish_loyalty_tier_definition (which would break the "Gapped
--    Program"/"Bad Dimension Program" fixtures scripts/db-tests/customer-
--    loyalty-membership-tier.sql already relies on to prove the sweep's own
--    skip-isolation behavior); no base tier is auto-created.
-- 6. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
--    its own explicit `revoke execute on all functions in schema app from
--    public` statement before its final grants, and its public.* wrapper
--    explicitly revokes PUBLIC before granting authenticated/service_role.

-- ===========================================================================
-- 1. app.loyalty_program_tier_readiness -- composite return type, no
-- backing table.
-- ===========================================================================

create type app.loyalty_program_tier_readiness as (
  program_id uuid,
  published_tier_count integer,
  has_base_tier boolean,
  base_tier_id uuid,
  unsupported_dimension_tier_count integer,
  active_account_count integer,
  untiered_active_account_count integer,
  ready boolean
);

-- ===========================================================================
-- 2. app.get_loyalty_program_tier_readiness -- LYL:View, read-only.
-- ===========================================================================

create function app.get_loyalty_program_tier_readiness(
  p_tenant_id uuid,
  p_program_id uuid,
  p_actor_auth_user_id uuid
)
returns app.loyalty_program_tier_readiness
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
  v_base_tier app.loyalty_tier_definitions;
  v_result app.loyalty_program_tier_readiness;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Authority is checked above, BEFORE this lookup (design decision 3) --
  -- tenant_id and program_id are matched together, so a tenant-A program id
  -- passed under a different tenant_id is indistinguishable from a
  -- genuinely nonexistent one.
  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_not_found: % is not a loyalty program of tenant %', p_program_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  v_result.program_id := v_program.id;

  select count(*) into v_result.published_tier_count
    from app.loyalty_tier_definitions
    where tenant_id = p_tenant_id and program_id = p_program_id and status = 'published';

  select count(*) into v_result.unsupported_dimension_tier_count
    from app.loyalty_tier_definitions
    where tenant_id = p_tenant_id and program_id = p_program_id and status = 'published'
      and threshold_dimension <> 'earning_amount_ytd';

  -- Design decision 1: base-tier presence is independent of dimension
  -- support -- captured separately above.
  select * into v_base_tier from app.loyalty_tier_definitions
    where tenant_id = p_tenant_id and program_id = p_program_id and status = 'published' and threshold_value = 0
    order by tier_rank asc
    limit 1;
  v_result.has_base_tier := found;
  v_result.base_tier_id := v_base_tier.id;

  select count(*) into v_result.active_account_count
    from app.loyalty_accounts
    where tenant_id = p_tenant_id and program_id = p_program_id and status = 'active';

  -- Design decision 2: literal "never assigned a tier" count -- covers both
  -- the missing-base-tier case and the negative-computed-amount case
  -- without re-deriving app.recalculate_customer_loyalty_tier's own
  -- eligibility arithmetic.
  select count(*) into v_result.untiered_active_account_count
    from app.loyalty_accounts a
    where a.tenant_id = p_tenant_id and a.program_id = p_program_id and a.status = 'active'
      and not exists (
        select 1 from app.loyalty_account_tier_movements m where m.loyalty_account_id = a.id
      );

  v_result.ready := v_result.has_base_tier
    and v_result.unsupported_dimension_tier_count = 0
    and v_result.untiered_active_account_count = 0;

  return v_result;
end;
$$;

comment on function app.get_loyalty_program_tier_readiness is
  'ISS-2026-127 item 2: advisory, read-only, LYL:View-gated snapshot of whether a loyalty programme''s own published tier ladder can currently resolve every active enrolment to a tier. NEVER gates app.publish_loyalty_tier_definition or app.recalculate_customer_loyalty_tier -- both keep raising loudly on a genuine misconfiguration, exactly as designed. ready = has_base_tier AND unsupported_dimension_tier_count = 0 AND untiered_active_account_count = 0. Zero writes; never calls app.capture_audit_event.';

-- ===========================================================================
-- 3. Grants.
-- ===========================================================================

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.get_loyalty_program_tier_readiness(uuid, uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 4. public.* wrapper (RGL-394 Option 2): app is not exposed to PostgREST --
-- every externally-callable app.* function needs a matching thin
-- pass-through wrapper, enforced by scripts/db-tests/public-api-wrapper-
-- regression.sql's own exhaustive sweep, mirroring
-- 20260831230000_add_loyalty_earning_tier_and_points_posting_sweeps.sql's
-- own wrapper shape exactly (same grant set, same security mode).
-- ===========================================================================

create function public.get_loyalty_program_tier_readiness(p_tenant_id uuid, p_program_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_program_tier_readiness
language sql
stable
security definer
set search_path = app, public, pg_temp
as $wrap$
  select * from app.get_loyalty_program_tier_readiness(p_tenant_id, p_program_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_loyalty_program_tier_readiness(uuid, uuid, uuid) is
  'RGL-394 Option-2 wrapper: a thin security-definer pass-through to app.get_loyalty_program_tier_readiness, never a reimplementation.';

revoke execute on function public.get_loyalty_program_tier_readiness(uuid, uuid, uuid) from anon, authenticated, service_role, public;
grant execute on function public.get_loyalty_program_tier_readiness(uuid, uuid, uuid) to authenticated, service_role;
