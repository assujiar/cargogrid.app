-- CG-AUDIT-2026-09-02 B7 (second half, "Invoicing keyed off a hand-copied UUID; no
-- credit control"): the worklist-UI half (a real "Prepare invoice" form over
-- app.list_billable_readiness_handoffs) was fixed earlier this session
-- (20260915010000_create_list_billable_readiness_handoffs.sql), whose own header
-- explicitly names "app.check_customer_credit/credit control" as "a separate, larger,
-- deliberately excluded piece of work, untouched here." This migration closes that
-- second half.
--
-- Scoping, confirmed live before writing this migration (never assumed):
-- app.check_customer_credit (COM-157, 20260724310000_create_commercial_credit_
-- commercial_control.sql:520-634) is NOT a stub -- it already reads a real, live
-- app.credit_profiles row plus any currently-valid app.credit_profile_overrides row,
-- and persists every outcome (allow/blocked_no_profile/blocked_not_active/blocked_hold/
-- blocked_currency_mismatch/blocked_limit) to app.credit_check_snapshots. But two real
-- gaps remain, both closed here:
--   1. It never consults actual AR exposure (open/unpaid invoices) -- only the static
--      approved_limit_amount/override amount, so a customer already at their limit from
--      prior unpaid invoices could still be approved for a brand-new request that alone
--      sits under the limit. The function's own doc comment discloses this as deliberate
--      at COM-157's own checkpoint ("no exposure/balance figure is ever consulted or
--      invented") -- but nothing in this repository ever built the exposure-aware
--      version that comment implies is still open work.
--   2. It is dead-gated code: repo-wide grep confirms app.check_customer_credit is only
--      ever reachable through its own public.check_customer_credit PostgREST wrapper
--      (20260826000000_create_public_api_data_wrappers.sql:4686), and the only caller
--      anywhere is a standalone, manual "Check eligibility" self-service widget on the
--      Account detail page (credit-check-form.tsx/credit-panel.tsx) -- no job-order or
--      shipment-order acceptance path calls it at all. Of every candidate acceptance
--      RPC (app.prepare_job_order_handoff, app.prepare_job_order, app.confirm_job_order,
--      app.create_shipment_order_from_job, app.confirm_shipment_order -- all confirmed
--      live, none call any credit check), app.prepare_job_order_handoff is the correct,
--      singular gate point: it is the one Commercial-side, quote-to-job-order
--      conversion moment where a requested amount (the quotation's own real total) and
--      the converted account are both concretely known, matching check_customer_credit's
--      own doc comment calling itself "the one deterministic, reproducible
--      pre-conversion check." app.confirm_job_order/app.confirm_shipment_order are pure
--      status transitions with no new financial-exposure decision -- gating there would
--      be a duplicate, later check, not the acceptance moment itself.
--
-- Fix 1: app.check_customer_credit now sums app.finance_ar_open_items.open_amount
-- (FIN-196, status <> 'paid', same currency) for the account and adds it to
-- p_requested_amount before comparing against the effective limit -- reading the base
-- table directly, NOT app.get_finance_ar_exposure_summary (which hard-gates on
-- app.check_finance_ar_authority('View', ...), i.e. FIN:View; routing through it would
-- force a permission regression onto every credit check, which only ever required
-- COM:View). check_customer_credit is already security definer with its own COM:View +
-- audit-snapshot boundary, so a direct table read here is the same trust boundary its
-- own profile/override lookups already use. No new outcome value, no new
-- credit_check_snapshots column, no contract/signature change -- blocked_limit now
-- means "existing open AR plus this request exceeds the limit," not "this request
-- alone."
--
-- Fix 2: app.prepare_job_order_handoff now calls app._evaluate_customer_credit (a new
-- internal decision core factored out of app.check_customer_credit -- see below) right
-- after the existing account_not_converted check and before assembling the payload,
-- and raises credit_blocked when the outcome represents an affirmative credit-control
-- decision -- so the credit_check_snapshots row app.build_job_order_draft_payload's own
-- "credit" field already surfaces for display becomes a real gating decision, not a
-- decorative value nobody ever asked for. The gate reuses this repository's own
-- existing credit-control precedent (COM-157's "soft decision row + permissioned,
-- reasoned, time-boxed override" shape, versus e.g. OPS-176's stricter unconditional
-- hard-block-with-no-override for dispatch readiness): no new bypass code is written
-- here. app.create_credit_override (COM:Approve + a fresh reauth confirmation within 5
-- minutes, unchanged by this migration) already inserts a bounded, reasoned,
-- always-expiring override row that app._evaluate_customer_credit's own override
-- lookup already consults -- an approver overriding via the existing credit-panel.tsx
-- widget makes this new gate see 'allow' transparently on the next attempt, with zero
-- new override plumbing.
--
-- Internal decision core, not the public RPC: a first draft of this migration had
-- app.prepare_job_order_handoff call the public app.check_customer_credit directly,
-- reasoning that "every Commercial role holding COM:Edit already holds COM:View, so
-- the transitive extra gate is harmless." That assumption was untested and wrong,
-- confirmed live by running this repository's own full `pnpm run db:test`:
-- scripts/db-tests/customer-booking-requests.sql's own staff role holds COM:Edit but
-- not COM:View, and broke with insufficient_authority on a function it had always
-- been able to call. Rather than patch every one of the 60+ existing
-- prepare_job_order_handoff callers' own role fixtures one at a time (a much larger,
-- riskier footprint touching capabilities this slice has nothing to do with), the
-- fix is app._evaluate_customer_credit: the exact same profile/override/AR-exposure
-- decision logic and snapshot write, with no authority check of its own, callable by
-- any already-gated function without imposing a second, transitive one. Confirmed
-- clean afterward via the same full db:test run.
--
-- Deliberate scope boundary on WHICH outcomes hard-block (disclosed, not silently
-- narrowed): the gate blocks on 'blocked_limit' / 'blocked_hold' / 'blocked_not_active'
-- / 'blocked_currency_mismatch' -- every outcome that represents an affirmative
-- credit-control decision already in force for that account -- but deliberately NOT on
-- 'blocked_no_profile'. Credit profiles are opt-in in this product today
-- (app.request_customer_credit_profile is a user-initiated action, never automatic),
-- confirmed live: scripts/db-tests/commercial-job-order-lineage.sql's own existing
-- happy-path handoff tests never set up a credit profile for their test accounts at
-- all. Hard-blocking every account that has simply never engaged credit control would
-- retroactively make a credit profile mandatory before ANY job order could ever be
-- accepted for ANY account -- a far larger, undisclosed product-shape change than "the
-- limit a tenant already approved should actually be enforced," and would break that
-- existing test's own already-VERIFIED happy path. Making credit-profile setup
-- mandatory tenant-wide, if ever wanted, is a real product decision for a human to make
-- explicitly -- not something this migration should smuggle in as a side effect of
-- closing an audit finding about AR exposure and gate wiring.
--
-- One more disclosed transactional subtlety: app._evaluate_customer_credit always
-- inserts a real snapshot row -- true in isolation, but PL/pgSQL has no
-- autonomous-transaction primitive (unlike Oracle), so when app.prepare_job_order_
-- handoff calls it and then itself raises credit_blocked moments later in the same
-- statement/transaction, that later raise unwinds the whole statement, including the
-- snapshot insert just made -- no committed audit row survives for that specific
-- blocked handoff attempt. This is the same "audit only after every precondition has
-- already passed" discipline app.prepare_job_order_handoff's own body already follows
-- for its other precondition failures (quote_not_accepted, account_not_converted,
-- etc. -- none of those leave an audit_logs row either), so this is not a new
-- inconsistency introduced here, only the same existing discipline now also applying
-- to the one new precondition this migration adds. A standalone call to
-- app.check_customer_credit (e.g. the existing manual "Check eligibility" widget, or
-- any future caller that does not itself raise
-- afterward) still gets its own full, permanent snapshot exactly as COM-157 designed.

-- Internal decision core (no permission check of its own), extracted so
-- app.prepare_job_order_handoff can reuse the exact same profile/override/AR-exposure
-- logic and snapshot-write without a SECOND, transitive COM:View authority check on
-- top of its own already-established COM:Edit gate. Confirmed live, the hard way,
-- before finalizing this shape: a naive first draft had app.prepare_job_order_handoff
-- call the public app.check_customer_credit directly, which broke
-- scripts/db-tests/customer-booking-requests.sql (its own staff role holds COM:Edit
-- but not COM:View) -- proof that "every COM:Edit role already holds COM:View" was
-- NOT a safe assumption across this repository's 60+ existing prepare_job_order_
-- handoff callers, not something to leave as an untested assumption. Always returns
-- the fully unmasked figures (masking is a caller-side concern, mirroring the
-- "snapshot is always unmasked, masking happens only on a returned projection"
-- discipline app.check_customer_credit itself already established) -- never called
-- directly by an ordinary session (mirrors app.build_job_order_draft_payload's own
-- identical "internal helper, security definer as defense in depth" precedent).
create function app._evaluate_customer_credit(
  p_tenant_id uuid,
  p_account_id uuid,
  p_currency text,
  p_requested_amount numeric,
  p_context_type text,
  p_context_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid,
  credit_profile_id uuid,
  profile_status_at_check text,
  currency text,
  requested_amount numeric,
  effective_limit_amount numeric,
  outcome text,
  checked_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_profile app.credit_profiles;
  v_override app.credit_profile_overrides;
  v_current_exposure numeric;
  v_effective_limit numeric;
  v_outcome text;
  v_snapshot app.credit_check_snapshots;
begin
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid_currency: % is not a 3-letter ISO currency code', p_currency using errcode = 'check_violation';
  end if;

  if p_requested_amount is null or p_requested_amount < 0 then
    raise exception 'invalid_amount: requested_amount must be non-negative' using errcode = 'check_violation';
  end if;

  select * into v_profile
  from app.credit_profiles
  where tenant_id = p_tenant_id and account_id = p_account_id and status in ('active', 'held', 'expired')
  order by created_at desc
  limit 1;

  if not found then
    insert into app.credit_check_snapshots (
      tenant_id, account_id, credit_profile_id, profile_status_at_check, profile_record_version,
      context_type, context_id, currency, requested_amount, effective_limit_amount, outcome, checked_by
    ) values (
      p_tenant_id, p_account_id, null, null, null, p_context_type, p_context_id, p_currency, p_requested_amount, null, 'blocked_no_profile', p_actor_label
    )
    returning * into v_snapshot;
    return query select v_snapshot.id, v_snapshot.credit_profile_id, v_snapshot.profile_status_at_check, v_snapshot.currency, v_snapshot.requested_amount, v_snapshot.effective_limit_amount, v_snapshot.outcome, v_snapshot.checked_at;
    return;
  end if;

  if v_profile.status = 'active' and v_profile.effective_to is not null and v_profile.effective_to <= now() then
    update app.credit_profiles cp set status = 'expired', updated_at = now(), record_version = record_version + 1
    where cp.id = v_profile.id
    returning cp.* into v_profile;
  end if;

  if v_profile.status = 'held' then
    v_outcome := 'blocked_hold';
    v_effective_limit := null;
  elsif v_profile.status <> 'active' then
    v_outcome := 'blocked_not_active';
    v_effective_limit := null;
  elsif v_profile.currency <> p_currency then
    v_outcome := 'blocked_currency_mismatch';
    v_effective_limit := null;
  else
    select * into v_override
    from app.credit_profile_overrides o
    where o.credit_profile_id = v_profile.id and o.expires_at > now()
    order by o.created_at desc
    limit 1;

    -- CG-AUDIT-2026-09-02 B7: real AR exposure, not just the static limit. Reads
    -- app.finance_ar_open_items (FIN-196) directly -- not app.get_finance_ar_exposure_
    -- summary, which hard-gates on FIN:View and would force a permission regression
    -- onto every caller of this function.
    select coalesce(sum(ar.open_amount), 0) into v_current_exposure
    from app.finance_ar_open_items ar
    where ar.tenant_id = p_tenant_id and ar.customer_account_id = p_account_id
      and ar.status <> 'paid' and ar.currency = p_currency;

    v_effective_limit := coalesce(v_override.amount, v_profile.approved_limit_amount);
    v_outcome := case when (v_current_exposure + p_requested_amount) <= v_effective_limit then 'allow' else 'blocked_limit' end;
  end if;

  insert into app.credit_check_snapshots (
    tenant_id, account_id, credit_profile_id, profile_status_at_check, profile_record_version,
    override_id, context_type, context_id, currency, requested_amount, effective_limit_amount, outcome, checked_by
  ) values (
    p_tenant_id, p_account_id, v_profile.id, v_profile.status, v_profile.record_version,
    v_override.id, p_context_type, p_context_id, p_currency, p_requested_amount, v_effective_limit, v_outcome, p_actor_label
  )
  returning * into v_snapshot;

  return query select v_snapshot.id, v_snapshot.credit_profile_id, v_snapshot.profile_status_at_check, v_snapshot.currency, v_snapshot.requested_amount, v_snapshot.effective_limit_amount, v_snapshot.outcome, v_snapshot.checked_at;
end;
$$;

comment on function app._evaluate_customer_credit is
  'CG-AUDIT-2026-09-02 B7: internal decision core shared by app.check_customer_credit (adds the COM:View gate + per-caller masking) and app.prepare_job_order_handoff (already gated on COM:Edit -- no second, transitive authority check). Always returns fully unmasked figures; every outcome (allow/blocked_no_profile/blocked_not_active/blocked_hold/blocked_currency_mismatch/blocked_limit) is a real, structurally distinct value on the persisted app.credit_check_snapshots row, never a bare boolean. blocked_limit reflects real AR exposure (app.finance_ar_open_items, status <> paid, same currency) added to the requested amount. Never called directly by an ordinary session.';

revoke execute on function app._evaluate_customer_credit(uuid, uuid, text, numeric, text, uuid, uuid, text) from public;
grant execute on function app._evaluate_customer_credit(uuid, uuid, text, numeric, text, uuid, uuid, text) to service_role;

create or replace function app.check_customer_credit(
  p_tenant_id uuid,
  p_account_id uuid,
  p_currency text,
  p_requested_amount numeric,
  p_context_type text,
  p_context_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns table (
  id uuid,
  credit_profile_id uuid,
  profile_status_at_check text,
  currency text,
  requested_amount numeric,
  effective_limit_amount numeric,
  amount_masked boolean,
  outcome text,
  checked_at timestamptz
)
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_masked boolean;
  v_row record;
begin
  v_masked := not app.has_view_selling_price(p_tenant_id, p_actor_auth_user_id);
  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'COM', 'View');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:View (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_row from app._evaluate_customer_credit(p_tenant_id, p_account_id, p_currency, p_requested_amount, p_context_type, p_context_id, p_actor_auth_user_id, p_actor_label);

  return query select
    v_row.id, v_row.credit_profile_id, v_row.profile_status_at_check,
    case when v_masked then null else v_row.currency end,
    case when v_masked then null else v_row.requested_amount end,
    case when v_masked then null else v_row.effective_limit_amount end,
    v_masked, v_row.outcome, v_row.checked_at;
end;
$$;

comment on function app.check_customer_credit is
  'COM-157, hardened CG-AUDIT-2026-09-02 B7: the one deterministic, reproducible pre-conversion check -- COM:View gate plus per-caller masking (COM:View selling price) over app._evaluate_customer_credit''s own decision core, the same "mask the function''s own output, not just a view" technique app.get_effective_customer_price (COM-156) and app.search_vendor_rates (COM-149) already established. blocked_limit now reflects real AR exposure (app.finance_ar_open_items, status <> paid, same currency) added to the requested amount, not the requested amount alone -- the function''s own original COM-157 doc comment disclosed the no-exposure-check gap as deliberate at that checkpoint; this migration closes it. The persisted app.credit_check_snapshots row is always fully unmasked (the source of truth).';

create or replace function app.prepare_job_order_handoff(
  p_quotation_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.job_order_handoffs
language plpgsql
security definer
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_quotation app.quotations;
  v_decision app.rbac_decision;
  v_conversion app.account_conversions;
  v_existing app.job_order_handoffs;
  v_credit record;
  v_payload jsonb;
  v_handoff app.job_order_handoffs;
begin
  select * into v_quotation from app.quotations where id = p_quotation_id;
  if not found then
    raise exception 'quotation_not_found: %', p_quotation_id using errcode = 'no_data_found';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_quotation.tenant_id, 'COM', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks COM:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_quotation.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_quotation.tenant_id, v_quotation.owner_user_id, app.lead_record_scope_org_unit_ids(v_quotation.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access quotation %', p_actor_auth_user_id, p_quotation_id
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent: an existing handoff for this exact (tenant, quotation, purpose) is
  -- returned unchanged -- never rebuilt, never duplicated (Prompt 160 §24).
  select * into v_existing from app.job_order_handoffs where tenant_id = v_quotation.tenant_id and quotation_id = p_quotation_id and purpose = 'job_order_draft';
  if found then
    if not app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then
      v_existing.payload := null;
      v_existing.payload_hash := null;
    end if;
    return v_existing;
  end if;

  if not v_quotation.is_current then
    raise exception 'not_current_version: quotation % version % is not the current version', p_quotation_id, v_quotation.version_number using errcode = 'check_violation';
  end if;
  if v_quotation.status <> 'submitted' then
    raise exception 'quote_not_submitted: quotation % is % and cannot be handed off', p_quotation_id, v_quotation.status using errcode = 'check_violation';
  end if;
  if v_quotation.approval_status not in ('approved', 'not_required') then
    raise exception 'quote_not_approved: quotation % approval_status is %', p_quotation_id, v_quotation.approval_status using errcode = 'check_violation';
  end if;
  if v_quotation.customer_decision is distinct from 'accepted' then
    raise exception 'quote_not_accepted: quotation % has not been accepted by the customer', p_quotation_id using errcode = 'check_violation';
  end if;

  select * into v_conversion from app.account_conversions where quotation_id = p_quotation_id;
  if not found then
    raise exception 'account_not_converted: quotation % has not been converted to an account', p_quotation_id using errcode = 'check_violation';
  end if;

  -- CG-AUDIT-2026-09-02 B7: the one, singular acceptance-moment credit gate (see this
  -- migration's own header for why this function, not confirm_job_order/confirm_
  -- shipment_order, is the correct gate point). Calls app._evaluate_customer_credit
  -- directly -- the shared internal decision core, not the public app.check_customer_
  -- credit -- so this already-COM:Edit-gated function never imposes a second,
  -- transitive COM:View requirement on its own callers (see this migration's own
  -- header for the real db-test regression that discovered this). Same transaction,
  -- same actor, no re-derived decision logic; its own snapshot insert fires for real
  -- here, so the credit_check_snapshots row app.build_job_order_draft_payload already
  -- surfaces into the payload's own "credit" field becomes a genuine gating decision,
  -- not a decorative display value. Blocked outcomes are never silently retried
  -- around: an authorized approver clears them via the existing
  -- app.create_credit_override (COM:Approve + fresh reauth), which
  -- app._evaluate_customer_credit's own override lookup already consults on the next
  -- attempt -- no new override plumbing is introduced here.
  select * into v_credit
  from app._evaluate_customer_credit(
    v_quotation.tenant_id, v_conversion.account_id, v_quotation.currency, v_quotation.total_amount,
    'job_order_handoff', p_quotation_id, p_actor_auth_user_id, p_actor_label
  );
  -- blocked_no_profile deliberately does not raise here -- see this migration's own
  -- header for why (credit profiles are opt-in, not mandatory).
  if v_credit.outcome in ('blocked_limit', 'blocked_hold', 'blocked_not_active', 'blocked_currency_mismatch') then
    -- The effective limit is masked in this message exactly as app.check_customer_
    -- credit itself would mask it for the same caller (COM:View selling price) --
    -- app._evaluate_customer_credit's own return is always unmasked, so masking is
    -- this caller's own responsibility, the same discipline this function already
    -- applies to its own returned payload/payload_hash further below.
    raise exception 'credit_blocked: quotation % account % outcome % (effective limit %)',
      p_quotation_id, v_conversion.account_id, v_credit.outcome,
      case when app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then v_credit.effective_limit_amount::text else 'masked' end
      using errcode = 'check_violation';
  end if;

  v_payload := app.build_job_order_draft_payload(p_quotation_id);

  insert into app.job_order_handoffs (
    tenant_id, quotation_id, account_id, payload, payload_hash,
    prepared_by_auth_user_id, owner_user_id, org_unit_id, created_by
  ) values (
    v_quotation.tenant_id, p_quotation_id, v_conversion.account_id, v_payload, encode(digest(v_payload::text, 'sha256'), 'hex'),
    p_actor_auth_user_id, v_quotation.owner_user_id, v_quotation.org_unit_id, p_actor_label
  )
  returning * into v_handoff;

  perform app.capture_audit_event(
    v_quotation.tenant_id, p_actor_auth_user_id, p_actor_label, 'prepare_job_order_handoff',
    'app.job_order_handoffs', v_handoff.id, 'success', null, null,
    jsonb_build_object('quotation_id', p_quotation_id, 'account_id', v_conversion.account_id, 'payload_hash', v_handoff.payload_hash)
  );

  if not app.has_view_selling_price(v_quotation.tenant_id, p_actor_auth_user_id) then
    v_handoff.payload := null;
    v_handoff.payload_hash := null;
  end if;

  return v_handoff;
end;
$$;

comment on function app.prepare_job_order_handoff is
  'COM-160, hardened CG-AUDIT-2026-09-02 B7: the one gated entrypoint. Re-validates accepted/approved/current/converted preconditions fresh on every call and is idempotent on (tenant_id, quotation_id, purpose) -- a retry after the row already exists returns it unchanged. Now also calls app._evaluate_customer_credit (COM-157''s internal decision core, not the public app.check_customer_credit -- avoids imposing a second, transitive COM:View requirement on top of this function''s own COM:Edit gate) for the converted account and the quotation''s own real total, raising credit_blocked for an affirmative credit-control decision already in force (blocked_limit/blocked_hold/blocked_not_active/blocked_currency_mismatch) -- the singular real acceptance-moment credit gate this repository previously had zero of (CG-AUDIT-2026-09-02 B7''s own finding: "no order-acceptance path calls it"). Deliberately does NOT block on blocked_no_profile -- credit profiles are opt-in, not mandatory (see this migration''s own header). The effective limit in a credit_blocked message is masked per-caller (COM:View selling price), the same discipline this function already applies to its own returned payload/payload_hash. An authorized COM:Approve override via app.create_credit_override clears a block on the next attempt.';
