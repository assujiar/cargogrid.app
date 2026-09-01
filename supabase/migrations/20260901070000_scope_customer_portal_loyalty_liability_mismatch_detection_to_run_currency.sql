-- ISS-2026-136 item 2 (docs/runtime/KNOWN_ISSUES.md): mismatch DETECTION for
-- entitlements/redemptions inside app.execute_loyalty_liability_reconciliation_run
-- is tenant-wide, not currency-scoped, unlike every liability TOTAL it computes
-- (each of which is scoped to the run's own p_currency parameter). One corrupted
-- entitlement or redemption row therefore re-raises the identical exception on
-- EVERY currency-scoped run for that tenant, not only the run whose own currency
-- the row actually belongs to -- real, bounded operational noise (never a wrong
-- liability number; item 1, the number-correctness half, was already fixed at
-- 20260801270000).
--
-- Independently re-derived live before drafting (per this repository's own
-- standing near-miss on this exact function -- built from a migration file
-- instead of the live body -- disclosed at ISS-2026-134's own 2026-08-28
-- update): `select pg_get_functiondef(...)` against a fresh disposable database
-- with every migration applied through 20260901060000 confirms the CURRENT body
-- is byte-identical (modulo pg_get_functiondef's own formatting) to
-- 20260828070000's own body -- the function has not been replaced again since
-- the reward_internal_cost_missing exception type was added. This migration's
-- base body is that live-confirmed text, copied verbatim, including the
-- CPL-325 single-snapshot-atomicity shape (ONE top-level statement, three
-- jsonb_agg branches sharing one MVCC snapshot) -- never reconstructed from an
-- on-disk migration file, and never touching that shape.
--
-- ===========================================================================
-- The new invariant, stated as a ruling: an exception is raised on a run
-- exactly when the row it concerns is genuinely IN SCOPE for that run's own
-- liability computation.
--   - points: every run, regardless of currency (unchanged -- see below).
--   - entitlements: only the run matching the entitlement's own immutable
--     `currency` column -- the IDENTICAL predicate this same function already
--     uses a few lines below, gating whether the entitlement's value is
--     accumulated into cashback/discount/voucher_liability_total at all.
--   - redemptions, and the existing reward_internal_cost_missing exception:
--     only the run whose own p_currency equals the tenant's resolved default
--     currency -- the IDENTICAL predicate this same function already uses to
--     gate accumulation into reward_fulfillment_liability_total, and the exact
--     predicate 20260828070000 already applies to reward_internal_cost_missing
--     for this same reason.
--
-- Two currency guards added, nothing else. Every other line -- including the
-- single-snapshot read, the points loop, and the reward_internal_cost_missing
-- branch (already correctly scoped since 20260828070000) -- is byte-identical
-- to the live body this migration was built from.
--
-- The one honest tradeoff, disclosed rather than hidden: a mismatch on an
-- entitlement in a currency the tenant never actually runs reconciliation for
-- is no longer surfaced by ANY run. This is NOT a new coverage hole -- that
-- same currency's liability TOTAL was already never reported in exactly that
-- scenario (a tenant simply never runs a reconciliation in a currency it has
-- no real activity in has nothing to reconcile in that currency either way).
-- This change makes detection coverage congruent with total coverage, rather
-- than broader than it -- which is precisely why the prior shape produced
-- noise instead of signal: a defect out of scope for a run's own totals was
-- still blocking that same run's own certify.
--
-- Points is DELIBERATELY LEFT UNTOUCHED, and this is a load-bearing
-- distinction, not an oversight. Design decision 6 of the creating migration
-- (20260801250000_create_customer_portal_loyalty_liability_reconciliation_
-- analytics.sql) states points_liability_total is a RAW POINTS total with no
-- currency conversion -- points are not denominated in any currency at all,
-- so there is no v_account.currency column to compare against p_currency in
-- the first place (unlike entitlements, which carry a real, immutable,
-- NOT NULL `currency` column -- app.loyalty_benefit_entitlements.currency,
-- lbe_currency_check, never UPDATEd anywhere in this repository's migration
-- history -- checked directly before drafting this fix). A tenant-wide points
-- defect must stay caught on every run regardless of currency; currency-
-- scoping it would be a real, silent gate weakening on a tenant-wide
-- correctness invariant, not a noise-reduction fix. The regression this
-- migration adds asserts a forced points defect is STILL caught on an
-- off-currency run as the load-bearing anti-regression proof of this
-- exact distinction.
--
-- Additive enrichment: each of the two now-scoped exception types carries its
-- own scoping currency in `detail`, so the new scope is self-evident to staff
-- reading it later -- the entitlement exception carries the entitlement's own
-- `currency`; the redemption exception carries the run's own `p_currency`
-- (identical to the tenant's resolved default currency in every case it can
-- fire, by construction of its own new guard). `detail` is already a generic
-- `z.record(z.string(), z.unknown())` in the TypeScript contract (server/
-- contracts/customer-portal-loyalty-liability/customer-portal-loyalty-
-- liability.ts) and rendered as a raw JSON dump in the admin UI (app/(tenant)/
-- [tenantSlug]/admin/loyalty-liability/loyalty-liability-admin-panel.tsx) --
-- both verified directly before drafting; neither needs a schema or UI change
-- for an additional key on an already-loosely-typed jsonb blob.
--
-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): this migration carries its
-- own explicit `revoke execute on all functions in schema app from public`
-- statement before its final grants, the standing per-migration convention
-- since PLT-118.

create or replace function app.execute_loyalty_liability_reconciliation_run(
  p_tenant_id uuid,
  p_as_of timestamptz,
  p_currency text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  p_idempotency_key text default null,
  p_config_version integer default 1
)
returns app.loyalty_liability_reconciliation_runs
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_as_of timestamptz := coalesce(p_as_of, clock_timestamp());
  v_idem text;
  v_existing app.loyalty_liability_reconciliation_runs;
  v_run app.loyalty_liability_reconciliation_runs;
  v_points_total numeric := 0;
  v_cashback_total numeric := 0;
  v_discount_total numeric := 0;
  v_voucher_total numeric := 0;
  v_reward_total numeric := 0;
  v_account record;
  v_entitlement record;
  v_derived_status text;
  v_redemption record;
  v_derived_redemption_status text;
  v_point_mismatches jsonb[] := '{}';
  v_entitlement_mismatches jsonb[] := '{}';
  v_redemption_mismatches jsonb[] := '{}';
  v_cost_missing_mismatches jsonb[] := '{}';
  v_mismatch jsonb;
  v_exception_count integer;
  v_tenant_default_currency text;
  v_points_json jsonb;
  v_entitlement_json jsonb;
  v_redemption_json jsonb;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'LYL', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks LYL:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a valid ISO currency code' , p_currency using errcode = 'check_violation';
  end if;

  v_idem := coalesce(nullif(trim(p_idempotency_key), ''), 'liability-recon:' || to_char(v_as_of, 'YYYY-MM-DD') || ':' || p_currency);

  -- Idempotent short-circuit AFTER the authority check (mandatory pattern).
  -- Never recomputes on a replay -- a run's own totals/exceptions are
  -- exactly what they were the moment they were first computed.
  select * into v_existing from app.loyalty_liability_reconciliation_runs where tenant_id = p_tenant_id and idempotency_key = v_idem;
  if found then
    return v_existing;
  end if;

  -- The reward's own internal_cost has no currency column of its own
  -- (design decision 1) -- resolved once here as the tenant's own currency
  -- preference, mirroring app.issue_loyalty_benefit_entitlement's (CPL-321)
  -- own identical resolution for the same class of value.
  select default_currency into v_tenant_default_currency from app.resolve_tenant_locale(p_tenant_id);

  -- =========================================================================
  -- CPL-325 single-snapshot-atomicity shape (20260801310000, unmodified).
  -- ONE statement, three independent jsonb_agg() branches (one per source
  -- domain), each an exact row-for-row/column-for-column projection of what
  -- the three separate queries would select -- the points branch inlines
  -- the point-balance cache lookup as a correlated subquery in the SAME
  -- statement. ISS-2026-134 item 3 fix (20260828070000): the redemption
  -- branch's own jsonb_build_object now ALSO carries raw_internal_cost
  -- (r.internal_cost, WITHOUT the coalesce) alongside the existing coalesced
  -- internal_cost, so the loop below can distinguish "really 0" from "null,
  -- coalesced to 0" without a second, separately-snapshotted query.
  -- =========================================================================
  select
    (select coalesce(jsonb_agg(jsonb_build_object(
        'acct_id', ps.acct_id, 'live_available', ps.live_available,
        'cached_available', (select pb.available from app.loyalty_point_balances pb where pb.tenant_id = p_tenant_id and pb.loyalty_account_id = ps.acct_id)
      )), '[]'::jsonb)
     from (
       select le.loyalty_account_id as acct_id, sum(le.amount) as live_available
       from app.loyalty_point_ledger_entries le
       where le.tenant_id = p_tenant_id
       group by le.loyalty_account_id
     ) ps),
    (select coalesce(jsonb_agg(jsonb_build_object(
        'ent_id', e.id, 'benefit_type', e.benefit_type, 'currency', e.currency, 'value_amount', e.value_amount, 'cached_status', e.status,
        'latest_event_type', (select ev.event_type from app.loyalty_benefit_entitlement_events ev where ev.entitlement_id = e.id order by ev.created_at desc, ev.id desc limit 1)
      )), '[]'::jsonb)
     from app.loyalty_benefit_entitlements e
     where e.tenant_id = p_tenant_id),
    (select coalesce(jsonb_agg(jsonb_build_object(
        'rdm_id', rd.id, 'reward_id', r.id, 'cached_status', rd.status,
        'internal_cost', coalesce(r.internal_cost, 0), 'raw_internal_cost', r.internal_cost,
        'latest_event_type', (select ev.event_type from app.loyalty_redemption_events ev where ev.redemption_id = rd.id order by ev.created_at desc, ev.id desc limit 1)
      )), '[]'::jsonb)
     from app.loyalty_redemptions rd
     join app.loyalty_rewards r on r.id = rd.reward_id
     where rd.tenant_id = p_tenant_id and rd.reward_type in ('physical_item', 'service_credit'))
  into v_points_json, v_entitlement_json, v_redemption_json;

  -- =========================================================================
  -- Points: live per-account recomputation from the raw ledger (design
  -- decision 3), cross-checked against the cached derived balance for the
  -- exactness evidence unit (design decisions 7/8). greatest(...,0) is a
  -- defensive clamp only. Loop body byte-identical to the prior logic --
  -- sourced from the single-snapshot projection above, not a live query.
  --
  -- ISS-2026-136 item 2: DELIBERATELY NOT currency-scoped, unlike the two
  -- loops below. Points carry no currency of their own (design decision 6 --
  -- points_liability_total is a raw points total, never converted); a
  -- tenant-wide points defect must stay caught on EVERY currency-scoped run
  -- regardless of currency. Currency-scoping this block would be a real,
  -- silent gate weakening on a tenant-wide correctness invariant, not a
  -- noise-reduction fix -- do not add a currency predicate here.
  -- =========================================================================
  for v_account in select * from jsonb_to_recordset(v_points_json) as x(acct_id uuid, live_available numeric, cached_available numeric)
  loop
    v_points_total := v_points_total + greatest(v_account.live_available, 0);

    if v_account.cached_available is null then
      v_point_mismatches := v_point_mismatches || jsonb_build_object(
        'loyaltyAccountId', v_account.acct_id, 'expectedAvailable', v_account.live_available, 'actualAvailable', null, 'note', 'no cached app.loyalty_point_balances row found for an account with ledger activity'
      );
    elsif v_account.cached_available is distinct from v_account.live_available then
      v_point_mismatches := v_point_mismatches || jsonb_build_object(
        'loyaltyAccountId', v_account.acct_id, 'expectedAvailable', v_account.live_available, 'actualAvailable', v_account.cached_available
      );
    end if;
  end loop;

  -- =========================================================================
  -- Cashback/discount/voucher: current status independently re-derived
  -- purely from the append-only event log (design decision 7). Loop body
  -- sourced from the single-snapshot projection above, not a live query.
  --
  -- ISS-2026-136 item 2 fix: the mismatch DETECTION now carries the exact
  -- same `v_entitlement.currency = p_currency` guard the accumulation
  -- condition a few lines below it already uses -- an entitlement's own
  -- immutable currency column (NOT NULL, never UPDATEd) decides whether it
  -- is in scope for THIS run at all, for both purposes identically. `detail`
  -- now also names the entitlement's own currency (additive; ISS-2026-136
  -- item 2's own disclosed self-evidence enrichment).
  -- =========================================================================
  for v_entitlement in select * from jsonb_to_recordset(v_entitlement_json) as x(ent_id uuid, benefit_type text, currency text, value_amount numeric, cached_status text, latest_event_type text)
  loop
    v_derived_status := case v_entitlement.latest_event_type
      when 'issued' then 'issued'
      when 'redeemed' then 'redeemed'
      when 'reversed' then 'reversed'
      when 'expired' then 'expired'
      when 'held' then 'held'
      when 'released' then 'issued'
      else null
    end;

    if v_derived_status is distinct from v_entitlement.cached_status and v_entitlement.currency = p_currency then
      v_entitlement_mismatches := v_entitlement_mismatches || jsonb_build_object(
        'entitlementId', v_entitlement.ent_id, 'expectedStatus', v_derived_status, 'actualStatus', v_entitlement.cached_status, 'latestEventType', v_entitlement.latest_event_type, 'currency', v_entitlement.currency
      );
    end if;

    if v_derived_status in ('issued', 'held') and v_entitlement.currency = p_currency then
      if v_entitlement.benefit_type = 'cashback' then
        v_cashback_total := v_cashback_total + v_entitlement.value_amount;
      elsif v_entitlement.benefit_type = 'discount' then
        v_discount_total := v_discount_total + v_entitlement.value_amount;
      elsif v_entitlement.benefit_type = 'voucher' then
        v_voucher_total := v_voucher_total + v_entitlement.value_amount;
      end if;
    end if;
  end loop;

  -- =========================================================================
  -- Reward fulfillment exposure (design decision 5): physical_item/
  -- service_credit redemptions committed but not yet delivered, valued at
  -- the reward's own staff-only internal_cost (tenant-default-currency
  -- assumption, design decision 1, currency-scoped since CPL-324/
  -- 20260801270000). Loop body sourced from the single-snapshot projection
  -- above, not a live query. ISS-2026-134 item 3 fix (20260828070000): a
  -- null raw_internal_cost still contributes 0 to the total (unchanged) but
  -- also raises reward_internal_cost_missing, already correctly co-scoped
  -- with the accumulation's own `p_currency = v_tenant_default_currency`
  -- guard -- unchanged by this migration.
  --
  -- ISS-2026-136 item 2 fix: the redemption-status mismatch DETECTION now
  -- carries that SAME `p_currency = v_tenant_default_currency` guard --
  -- redemptions have no currency column of their own (design decision 1's
  -- tenant-default-currency assumption), so they are only ever in scope for
  -- the one run matching the tenant's own resolved default currency, for
  -- both the total and the mismatch check alike. `detail` now also names
  -- the run's own currency (additive; identical to the tenant's default
  -- currency in every case this can fire, by construction).
  -- =========================================================================
  for v_redemption in select * from jsonb_to_recordset(v_redemption_json) as x(rdm_id uuid, reward_id uuid, cached_status text, internal_cost numeric, raw_internal_cost numeric, latest_event_type text)
  loop
    v_derived_redemption_status := case v_redemption.latest_event_type
      when 'submitted' then 'pending_approval'
      when 'approved' then 'fulfilling'
      when 'rejected' then 'rejected'
      when 'cancelled' then 'cancelled'
      when 'fulfilled' then 'fulfilled'
      when 'fulfillment_failed' then 'failed'
      else null
    end;

    if v_derived_redemption_status is distinct from v_redemption.cached_status and p_currency = v_tenant_default_currency then
      v_redemption_mismatches := v_redemption_mismatches || jsonb_build_object(
        'redemptionId', v_redemption.rdm_id, 'expectedStatus', v_derived_redemption_status, 'actualStatus', v_redemption.cached_status, 'latestEventType', v_redemption.latest_event_type, 'currency', p_currency
      );
    end if;

    if v_derived_redemption_status = 'fulfilling' and p_currency = v_tenant_default_currency then
      v_reward_total := v_reward_total + v_redemption.internal_cost;

      if v_redemption.raw_internal_cost is null then
        v_cost_missing_mismatches := v_cost_missing_mismatches || jsonb_build_object(
          'redemptionId', v_redemption.rdm_id, 'rewardId', v_redemption.reward_id, 'note', 'reward.internal_cost is null on an actively fulfilling redemption -- contributes 0 to reward_fulfillment_liability_total'
        );
      end if;
    end if;
  end loop;

  v_exception_count := coalesce(array_length(v_point_mismatches, 1), 0) + coalesce(array_length(v_entitlement_mismatches, 1), 0) + coalesce(array_length(v_redemption_mismatches, 1), 0) + coalesce(array_length(v_cost_missing_mismatches, 1), 0);

  -- The run row's own INSERT establishes the idempotency claim FIRST -- a
  -- genuine concurrent duplicate-idempotency-key race is caught by the real
  -- exception handler below, mirroring every other posting-shaped RPC in
  -- this domain (design decision 9).
  begin
    insert into app.loyalty_liability_reconciliation_runs (
      tenant_id, as_of, currency, status,
      points_liability_total, cashback_liability_total, discount_liability_total, voucher_liability_total, reward_fulfillment_liability_total,
      config_version, idempotency_key, executed_by
    ) values (
      p_tenant_id, v_as_of, p_currency, case when v_exception_count > 0 then 'exceptions_pending' else 'open' end,
      v_points_total, v_cashback_total, v_discount_total, v_voucher_total, v_reward_total,
      coalesce(p_config_version, 1), v_idem, p_actor_label
    )
    returning * into v_run;
  exception
    when unique_violation then
      select * into v_run from app.loyalty_liability_reconciliation_runs where tenant_id = p_tenant_id and idempotency_key = v_idem;
      if not found then
        raise;
      end if;
      return v_run;
  end;

  foreach v_mismatch in array v_point_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'point_balance_derivation_mismatch', v_mismatch);
  end loop;

  foreach v_mismatch in array v_entitlement_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'entitlement_state_derivation_mismatch', v_mismatch);
  end loop;

  foreach v_mismatch in array v_redemption_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'redemption_liability_status_mismatch', v_mismatch);
  end loop;

  foreach v_mismatch in array v_cost_missing_mismatches loop
    insert into app.loyalty_liability_reconciliation_exceptions (tenant_id, run_id, exception_type, detail)
    values (p_tenant_id, v_run.id, 'reward_internal_cost_missing', v_mismatch);
  end loop;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_actor_label, 'execute_loyalty_liability_reconciliation_run',
    'app.loyalty_liability_reconciliation_runs', v_run.id, 'success', null, null,
    jsonb_build_object('currency', p_currency, 'exception_count', v_exception_count, 'status', v_run.status)
  );

  return v_run;
end;
$$;

comment on function app.execute_loyalty_liability_reconciliation_run is
  'CPL-323, hardened at CPL-324 (ISS-2026-136 item 1 currency-scope fix on the liability TOTALS), CPL-325 (single-snapshot atomicity fix, 20260801310000), 20260828070000 (ISS-2026-134 item 3, reward_internal_cost_missing), and again here (ISS-2026-136 item 2): one deterministic, reproducible Loyalty-liability reconciliation run, as of a recorded point in time. points_liability_total is a RAW POINTS total (no fabricated conversion rate); cashback/discount/voucher/reward_fulfillment totals are all currency-scoped to this run''s own currency column. Mismatch DETECTION is scoped identically to each domain''s own liability computation: points-balance mismatches are raised on every run (points carry no currency); entitlement-status mismatches are raised only on the run matching the entitlement''s own immutable currency; redemption-status and reward_internal_cost_missing mismatches are raised only on the run matching the tenant''s resolved default currency -- an exception no longer fires on a run for which the row it concerns was never actually in scope. All three source domains, plus the point-balance cache comparison, are read via ONE single top-level SQL statement -- one MVCC snapshot under READ COMMITTED. status=certified requires zero open exceptions on this run -- certification never silently forces equality.';

-- Per ERR-2026-004: explicit, directly-provable revoke of PostgreSQL's
-- PUBLIC-execute default, applied before any role-specific grant below.
revoke execute on all functions in schema app from public;

grant execute on function app.execute_loyalty_liability_reconciliation_run(uuid, timestamptz, text, uuid, text, text, integer) to authenticated, service_role;
