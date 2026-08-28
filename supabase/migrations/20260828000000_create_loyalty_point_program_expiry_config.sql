-- Track B Batch 4, ISS-2026-128 item 2 (docs/runtime/KNOWN_ISSUES.md).
--
-- Closes ISS-2026-128 item 2 (docs/runtime/KNOWN_ISSUES.md) on the terms its
-- own "Recommended fix" text already named: "an additive
-- app.loyalty_point_program_configs table (tenant_id, program_id,
-- points_expiry_days) this checkpoint's own migration deliberately did not
-- build, mirroring CPL-317's own review_period_days precedent."
--
-- Read in full before writing this file: supabase/migrations/
-- 20260801200000_create_customer_portal_loyalty_points_ledger.sql (CPL-318,
-- owns app.post_loyalty_points_earned, design decision 4 -- the function this
-- migration widens) and 20260801190000_create_customer_portal_loyalty_
-- membership_tier.sql (CPL-317, the review_period_days persisted-column
-- precedent this migration's own table mirrors in spirit, though as a
-- dedicated config table rather than a column on an existing row, since --
-- unlike a tier definition -- no existing per-program row in CPL-318's own
-- schema is the natural home for a program-wide points-expiry policy).
--
-- ===========================================================================
-- Design decisions (disclosed)
-- ===========================================================================
--
-- 1. **New table, not a column on app.loyalty_programs.** CPL-316 (`20260801
--    180000_create_customer_portal_loyalty_program_earning.sql`) owns app.
--    loyalty_programs and is an already-applied migration this task may not
--    edit in place; a new, additive, separately-owned config table (CPL-318's
--    own domain, since points-lot expiry is CPL-318's own concern, never
--    CPL-316's) is the correct additive shape, exactly mirroring how this
--    repository elsewhere adds a new table rather than reopening an
--    already-applied migration to widen an existing one (e.g. ISS-2026-130's
--    own resolution, a new migration adding a trigger to already-existing
--    tables, never a hand-edit of the tables' own original CREATE TABLE
--    migrations).
-- 2. **One row per (tenant_id, program_id), a real, bounded (1-3650)
--    points_expiry_days -- the identical bound app.post_loyalty_points_
--    earned's own p_expiry_days parameter already enforces**, so a
--    persisted config can never encode a value the RPC itself would reject.
--    No row for a program is a legitimate, expected state ("this program has
--    no persisted override -- the system default of 365 days applies"), not
--    an error -- app.get_loyalty_point_program_expiry_config returns NULL
--    for that case rather than raising a *_not_found exception (a deliberate
--    departure from app.get_loyalty_point_balance's own "not_found is an
--    error" precedent, because an absent balance row and an absent config
--    row mean different things: the former is "nothing has happened yet",
--    the latter is "the system default is the intended, current policy").
-- 3. **app.post_loyalty_points_earned is widened via CREATE OR REPLACE with
--    an IDENTICAL signature (uuid, uuid, uuid, text, integer) -- only its
--    own p_expiry_days parameter's default value changes, from a literal
--    365 to NULL.** Every existing call site in this repository (grep-
--    confirmed against every migration and this checkpoint's own db-test)
--    always passes p_expiry_days explicitly, so this default-value change is
--    a no-op for every caller that exists today; the only observable
--    behavior change is for a FUTURE caller that omits the 5th argument
--    entirely, which today always got the hardcoded 365 and will now get
--    the tenant/program's own persisted override when one has been set (and
--    365 as an unchanged fallback when it has not). p_expiry_days, when
--    explicitly supplied by any caller, continues to win outright over any
--    persisted config -- an explicit call-site override is never silently
--    superseded by a persisted default; this mirrors the general
--    "explicit argument beats persisted/derived default" convention this
--    repository already applies elsewhere (e.g. CPL-322's own p_run_label
--    parameter).
-- 4. **Resolution order inside app.post_loyalty_points_earned**: the existing
--    idempotency short-circuit (return the existing ledger row for a
--    replayed earning_event_id) still runs BEFORE any expiry-days
--    resolution, unchanged -- a replay never re-derives or re-validates an
--    expiry window, since the lot already exists. Config lookup (only when
--    p_expiry_days is NULL) happens AFTER the earning event is fetched and
--    validated (so the event's own loyalty_account_id -> program_id is
--    known), and BEFORE the bounded-range check and the lot INSERT --
--    functionally identical position to where the literal 365 default was
--    already being applied, just resolved from a real lookup instead of a
--    hardcoded literal when no explicit override is given.
-- 5. **RBAC**: app.set_loyalty_point_program_expiry_config requires the
--    elevated LYL:Configure authority (mirrors CPL-317's own "publishing a
--    tier definition" / this domain's established "changes what a future
--    computation resolves to" -> Configure precedent, since this config
--    changes the expiry window every FUTURE points-earning conversion for
--    the program will use); app.get_loyalty_point_program_expiry_config
--    requires only LYL:View, mirroring every other plain get_* RPC in this
--    domain.
-- 6. **RLS**: enabled, zero direct grant to `authenticated`, mirroring every
--    other table in this domain (design decision 16 of the CPL-318
--    migration this table extends) -- the two new RPCs below are the only
--    sanctioned access path.
-- 7. Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries
--    its own explicit `revoke execute on all functions in schema app from
--    public` statement before its final grants.

-- ===========================================================================
-- 1. app.loyalty_point_program_configs
-- ===========================================================================

create table app.loyalty_point_program_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references app.tenants (id),
  program_id uuid not null references app.loyalty_programs (id),
  points_expiry_days integer not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by_actor_label text not null,
  constraint lppc_expiry_days_check check (points_expiry_days between 1 and 3650),
  constraint lppc_tenant_program_unique unique (tenant_id, program_id)
);

comment on table app.loyalty_point_program_configs is
  'ISS-2026-128 item 2 fix: an optional, persisted per-(tenant,program) override for app.post_loyalty_points_earned''s own p_expiry_days policy knob. Absence of a row is a legitimate state (the 365-day system default applies), never an error. One row per program, upserted only via app.set_loyalty_point_program_expiry_config.';

create index lppc_tenant_updated_id_idx on app.loyalty_point_program_configs (tenant_id, updated_at desc, id desc);

-- ===========================================================================
-- 2. app.set_loyalty_point_program_expiry_config -- LYL:Configure. Upserts
-- the persisted override for one program.
-- ===========================================================================

create function app.set_loyalty_point_program_expiry_config(
  p_tenant_id uuid,
  p_program_id uuid,
  p_points_expiry_days integer,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.loyalty_point_program_configs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_program app.loyalty_programs;
  v_config app.loyalty_point_program_configs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Configure');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Configure (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_points_expiry_days < 1 or p_points_expiry_days > 3650 then
    raise exception 'invalid_expiry_days: % must be between 1 and 3650', p_points_expiry_days using errcode = 'check_violation';
  end if;

  select * into v_program from app.loyalty_programs where id = p_program_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'loyalty_program_not_found: % is not a loyalty program of tenant %', p_program_id, p_tenant_id using errcode = 'no_data_found';
  end if;

  insert into app.loyalty_point_program_configs (tenant_id, program_id, points_expiry_days, updated_by_actor_label)
  values (p_tenant_id, p_program_id, p_points_expiry_days, p_actor_label)
  on conflict (tenant_id, program_id) do update
    set points_expiry_days = excluded.points_expiry_days,
        updated_at = clock_timestamp(),
        updated_by_actor_label = excluded.updated_by_actor_label
  returning * into v_config;

  return v_config;
end;
$$;

comment on function app.set_loyalty_point_program_expiry_config is
  'ISS-2026-128 item 2 fix: upserts the persisted points-lot expiry window for one (tenant, program). LYL:Configure-gated -- changes what every FUTURE app.post_loyalty_points_earned call for the program resolves to when its own caller does not supply an explicit override.';

-- ===========================================================================
-- 3. app.get_loyalty_point_program_expiry_config -- LYL:View. Returns NULL
-- (never an error) when no override has been set.
-- ===========================================================================

create function app.get_loyalty_point_program_expiry_config(
  p_tenant_id uuid,
  p_program_id uuid,
  p_actor_auth_user_id uuid
)
returns app.loyalty_point_program_configs
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_config app.loyalty_point_program_configs;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_config from app.loyalty_point_program_configs where tenant_id = p_tenant_id and program_id = p_program_id;
  -- No row is a legitimate state (design decision 2) -- return NULL, never
  -- raise. v_config is already NULL-shaped (every field null) when "not
  -- found", which is what a plpgsql function returning a composite row type
  -- yields when the SELECT INTO finds nothing; returned as-is.
  return v_config;
end;
$$;

comment on function app.get_loyalty_point_program_expiry_config is
  'ISS-2026-128 item 2 fix: returns the persisted points-lot expiry override for one (tenant, program), or a NULL-shaped row when none has been set (the 365-day system default applies in that case) -- absence is never an error.';

-- ===========================================================================
-- 4. app.post_loyalty_points_earned -- widened (CREATE OR REPLACE, identical
-- signature) to consult the persisted config when no explicit override is
-- supplied (design decisions 3-4).
-- ===========================================================================

create or replace function app.post_loyalty_points_earned(
  p_tenant_id uuid,
  p_earning_event_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_expiry_days integer default null
)
returns app.loyalty_point_ledger_entries
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_expiry_days integer;
  v_idem text;
  v_existing app.loyalty_point_ledger_entries;
  v_event app.loyalty_earning_events;
  v_lot app.loyalty_point_lots;
  v_program_id uuid;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  -- ISS-2026-128 item 2 fix, ordering correction: an EXPLICIT caller-supplied
  -- p_expiry_days is validated HERE, unconditionally, before the idempotency
  -- short-circuit -- mirrors the original (pre-config) body's own behavior,
  -- where the single coalesce(p_expiry_days, 365) bounds check ran before
  -- the idempotency loop and so fired even on a replay call. Moving this
  -- into the loop (validating only after the idempotency check) would have
  -- silently skipped validation on any replay of an already-posted earning
  -- event, regressing that established contract -- self-caught by this
  -- checkpoint's own pre-existing regression in scripts/db-tests/customer-
  -- loyalty-points-ledger.sql (the "expected invalid_expiry_days for 0 days"
  -- replay-scenario assertion) before this migration was finalized. Only the
  -- NULL/config-resolution path (which genuinely needs the event's own
  -- program, unknown until the event is fetched) is deferred into the loop
  -- below.
  if p_expiry_days is not null and (p_expiry_days < 1 or p_expiry_days > 3650) then
    raise exception 'invalid_expiry_days: % must be between 1 and 3650', p_expiry_days using errcode = 'check_violation';
  end if;

  v_idem := 'earning-event:' || p_earning_event_id::text;

  loop
    select * into v_existing from app.loyalty_point_ledger_entries where tenant_id = p_tenant_id and idempotency_key = v_idem;
    if found then
      return v_existing;
    end if;

    select * into v_event from app.loyalty_earning_events where id = p_earning_event_id and tenant_id = p_tenant_id;
    if not found then
      raise exception 'loyalty_earning_event_not_found: % is not an earning event of tenant %', p_earning_event_id, p_tenant_id using errcode = 'no_data_found';
    end if;
    if v_event.reward_type <> 'points' then
      raise exception 'not_a_points_earning_event: earning event % has reward_type %, not points', p_earning_event_id, v_event.reward_type using errcode = 'check_violation';
    end if;
    if v_event.corrects_event_id is not null or v_event.source_type = 'reversal' then
      raise exception 'earning_event_is_a_reversal: % is a reversal earning event -- call app.reverse_loyalty_points_earned instead', p_earning_event_id using errcode = 'check_violation';
    end if;
    if v_event.amount <= 0 then
      raise exception 'invalid_earning_event_amount: earning event % has non-positive amount %', p_earning_event_id, v_event.amount using errcode = 'check_violation';
    end if;

    -- ISS-2026-128 item 2 fix: an explicit caller-supplied p_expiry_days
    -- still wins outright (design decision 3, already bounds-checked above
    -- before the idempotency short-circuit); only a NULL falls through to
    -- the persisted per-(tenant,program) config, and only a missing config
    -- row falls further through to the original 365-day literal default.
    if p_expiry_days is not null then
      v_expiry_days := p_expiry_days;
    else
      select la.program_id into v_program_id from app.loyalty_accounts la where la.id = v_event.loyalty_account_id and la.tenant_id = p_tenant_id;
      select ppc.points_expiry_days into v_expiry_days from app.loyalty_point_program_configs ppc where ppc.tenant_id = p_tenant_id and ppc.program_id = v_program_id;
      v_expiry_days := coalesce(v_expiry_days, 365);

      -- Defense-in-depth only: app.loyalty_point_program_configs already
      -- enforces this same bound at the table level (lppc_expiry_days_check)
      -- and app.set_loyalty_point_program_expiry_config re-validates it
      -- before ever writing a row, so this branch is structurally
      -- unreachable today -- kept in case a future direct write path to the
      -- config table is ever added without going through that RPC.
      if v_expiry_days < 1 or v_expiry_days > 3650 then
        raise exception 'invalid_expiry_days: % must be between 1 and 3650', v_expiry_days using errcode = 'check_violation';
      end if;
    end if;

    begin
      insert into app.loyalty_point_lots (tenant_id, loyalty_account_id, source_earning_event_id, original_amount, remaining_amount, expires_at, status)
      values (p_tenant_id, v_event.loyalty_account_id, p_earning_event_id, v_event.amount, v_event.amount, clock_timestamp() + make_interval(days => v_expiry_days), 'active')
      returning * into v_lot;
      exit;
    exception
      when unique_violation then
        -- Lost a concurrent lot-creation race for the SAME earning event
        -- (lpl_tenant_source_earning_event_unique); loop back -- the
        -- idempotency check above will see the winner's committed ledger
        -- row once it exists (design decision 2's own PostgreSQL unique-
        -- constraint blocking-then-resolving behavior).
        continue;
    end;
  end loop;

  return app.post_loyalty_point_ledger_entry(
    p_tenant_id, v_event.loyalty_account_id, 'earn', v_event.amount, v_lot.id,
    'loyalty_earning_event', p_earning_event_id, v_idem, null, null,
    p_actor_auth_user_id, p_actor_label
  );
end;
$$;

comment on function app.post_loyalty_points_earned is
  'CPL-318, widened per ISS-2026-128 item 2: idempotent on (tenant_id, ''earning-event:'' || earning_event_id) -- calling this twice for the same earning event is a safe no-op, never a duplicate lot or ledger entry. Rejects a non-points, a reversal-shaped, or a non-positive-amount earning event. p_expiry_days (1-3650, default NULL) -- an explicit value always wins; NULL falls through to the program''s own persisted app.loyalty_point_program_configs override when one exists, and further to a 365-day system default when it does not.';

-- ===========================================================================
-- 5. RLS -- enable, grant service_role only, mirroring every other table in
-- this domain (design decision 6).
-- ===========================================================================

alter table app.loyalty_point_program_configs enable row level security;

grant select, insert, update on app.loyalty_point_program_configs to service_role;

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable
-- revoke of PostgreSQL's PUBLIC-execute default, the standing per-migration
-- convention since PLT-118, applied here before any role-specific grant.
revoke execute on all functions in schema app from public;

grant execute on function app.set_loyalty_point_program_expiry_config(uuid, uuid, integer, uuid, text) to authenticated, service_role;
grant execute on function app.get_loyalty_point_program_expiry_config(uuid, uuid, uuid) to authenticated, service_role;

-- ===========================================================================
-- 6. public.* wrappers (RGL-394 Option 2): app is not exposed to PostgREST --
-- every externally-callable app.* function needs a matching thin pass-through
-- wrapper, enforced by scripts/db-tests/public-api-wrapper-regression.sql's
-- own exhaustive sweep. Self-caught: an earlier draft of this migration
-- omitted these two wrappers entirely and was caught by that regression
-- check before being finalized.
-- ===========================================================================

create function public.set_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_points_expiry_days integer, p_actor_auth_user_id uuid, p_actor_label text)
returns app.loyalty_point_program_configs
language sql
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.set_loyalty_point_program_expiry_config(p_tenant_id, p_program_id, p_points_expiry_days, p_actor_auth_user_id, p_actor_label);
$wrap$;

comment on function public.set_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_points_expiry_days integer, p_actor_auth_user_id uuid, p_actor_label text) is
  'RGL-394 Option 2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.set_loyalty_point_program_expiry_config with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.set_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_points_expiry_days integer, p_actor_auth_user_id uuid, p_actor_label text) from public;
grant execute on function public.set_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_points_expiry_days integer, p_actor_auth_user_id uuid, p_actor_label text) to service_role;
grant execute on function public.set_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_points_expiry_days integer, p_actor_auth_user_id uuid, p_actor_label text) to authenticated;

create function public.get_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_actor_auth_user_id uuid)
returns app.loyalty_point_program_configs
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $wrap$
  select * from app.get_loyalty_point_program_expiry_config(p_tenant_id, p_program_id, p_actor_auth_user_id);
$wrap$;

comment on function public.get_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_actor_auth_user_id uuid) is
  'RGL-394 Option 2 wrapper: app is not exposed to PostgREST; this is a thin security-definer pass-through to app.get_loyalty_point_program_expiry_config with an identical grant set, never a reimplementation. See docs/build-log/release-go-live/RGL-394.md.';

revoke execute on function public.get_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_actor_auth_user_id uuid) from public;
grant execute on function public.get_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_actor_auth_user_id uuid) to service_role;
grant execute on function public.get_loyalty_point_program_expiry_config(p_tenant_id uuid, p_program_id uuid, p_actor_auth_user_id uuid) to authenticated;
