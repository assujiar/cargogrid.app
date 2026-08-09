-- Prompt 269 (CG-S11-PRC-020, Procurement/Vendor Integrity, Security and Financial
-- Hardening) -- Fix 3, closing ISS-2026-045 (HIGH): the currency-blind procurement
-- approval threshold. `app.evaluate_procurement_approval_requirement` (originally
-- `20260730660000_create_procurement_approval.sql`, already amended once by
-- `20260730670000_harden_procurement_batch_257_259_review_fixes.sql` to add the
-- `assert_actor_is_session_identity` call preserved verbatim below) compared
-- `p_value_amount >= v_policy.min_value_amount` as raw numerics with NO currency
-- dimension at all -- a 6,000 IDR rate_version (~USD 0.40) and a 6,000 USD rate_version
-- (genuinely large) got the identical required=true/false verdict. Governs three
-- value-bearing entity types: `rate_version` (`app.vendor_rate_versions.base_amount`),
-- `vendor_selection` (`app.vendor_comparison_offers.normalized_amount`, already
-- normalized into `app.vendor_comparisons.comparison_currency` by PRC-258's own
-- machinery), and `purchase_order` (`app.purchase_orders.total_amount`/`currency`). The
-- three OTHER entity types (`vendor_activation`/`vendor_contract`/`exception_override`)
-- can never carry `min_value_amount` at all -- enforced by the pre-existing, untouched
-- `procurement_approval_policies_value_dimension_check` CHECK constraint -- so this fix
-- structurally cannot reach them (see the regression tests proving that unreachability).
--
-- ===========================================================================
-- Design, decided upstream (Prompt 269's own §3/§4 for this fix; implemented verbatim)
-- ===========================================================================
--
-- The shared private helper `app._request_procurement_entity_approval` (same
-- `20260730660000` file) already receives a `p_currency` parameter from every one of
-- its 5 call sites today (`app.decide_vendor_profile_review` passes null/null for
-- `vendor_activation`; `app.create_rate_version` passes `p_base_amount, p_currency` for
-- `rate_version`; `app.submit_vendor_comparison_for_approval` passes
-- `v_offer.normalized_amount, v_comparison.comparison_currency` for `vendor_selection`;
-- `app.submit_purchase_order_for_approval` -- the CURRENT version in
-- `20260730690000_harden_procurement_purchase_order_batch_260_review_fixes.sql`, not
-- the superseded one in `20260730680000` -- passes `v_po.total_amount, v_po.currency`
-- for `purchase_order`; `app.create_procurement_exception_request` passes null/null for
-- `exception_override`) -- it was used only to populate the
-- `procurement_approval_context_snapshots.currency` column, never fed into the actual
-- threshold comparison. The ONLY code path missing is threading `p_currency` from
-- `_request_procurement_entity_approval`'s own body into
-- `evaluate_procurement_approval_requirement`'s own call -- none of the 5 entity-type
-- submit/transition RPCs themselves need to change, only these two shared functions
-- plus the policy table/version-creation RPC that now needs a currency dimension to
-- compare against.
--
-- A new `app.procurement_approval_policies.policy_currency` column (default 'USD',
-- validated via the existing, FIN-194-backed `app.validate_currency_code`) records the
-- currency `min_value_amount` is denominated in. When the incoming value's own currency
-- matches the policy's `policy_currency` (or no currency was supplied at all -- the
-- legacy, pre-this-fix call shape), the comparison is unchanged, byte-for-byte, from
-- today. When it differs, a new private helper `app._evaluate_procurement_currency_
-- threshold` -- a DELIBERATE, DISCLOSED VARIANT of PRC-258's own precedent
-- `app._normalize_vendor_comparison_currency` (`20260730650000_create_procurement_
-- vendor_comparison.sql`), not an identical copy -- converts it via the same
-- `app.convert_finance_amount` (FIN-194) machinery vendor comparison already composes.
--
-- **The variant, and why it exists.** PRC-258's own precedent lets `insufficient_
-- privilege` (the actor lacks FIN:View) propagate uncaught, because its own caller
-- already proactively checks `app.check_finance_exchange_rate_authority('View', ...)`
-- before ever reaching that helper (design note 7 of that migration). This evaluator's
-- own actor gate is DELIBERATELY `app.has_active_tenant_membership` only (the existing
-- design-note comment preserved verbatim in the function body below) -- a caller whose
-- own authority model is not the PRC permission catalogue at all (`app.create_rate_
-- version`'s own `app.is_support_grant_authority`, unrelated to `FIN:View`) must still
-- be able to reach this evaluator. If that caller does not separately hold FIN:View, a
-- raw `insufficient_privilege` raised by `convert_finance_amount` would abort the
-- ENTIRE submit transaction (rate-version/PO/vendor-selection creation), a far worse
-- regression than the governance question itself. So `app._evaluate_procurement_
-- currency_threshold` ALSO catches `insufficient_privilege` (narrowly, by message
-- prefix, alongside the same `no_data_found`/`check_violation` conditions the
-- precedent already catches) and folds it into the SAME "conversion unavailable"
-- outcome.
--
-- **Fail CLOSED, not open, on ANY conversion-unavailable outcome** (missing FX rate,
-- unsupported currency, OR actor lacks FIN:View): treat the threshold as met
-- (`required=true`, reason `'value_currency_unverifiable_defaulted_to_required'`)
-- rather than silently skipping governance. Per ISS-2026-045's own explicit reasoning,
-- under-routing (silently skipping a review a large foreign-currency value should have
-- triggered) is the more dangerous direction than over-routing -- "governance ran but
-- could not verify magnitude" must resolve to "review it," never "skip it." A future
-- reader must not "fix" this back to fail-open -- that would silently reopen the exact
-- ~15,000x USD/IDR skew this migration closes, for the one case (no FX rate configured,
-- or a caller with no FIN:View) where verification itself is unavailable.
--
-- ===========================================================================
-- Applied migration discipline (AGENTS.md)
-- ===========================================================================
--
-- Every already-applied migration file referenced above is read-only from here on.
-- CORRECTION, VERIFIED LIVE rather than assumed (this file's own governing prompt said
-- "do not assume it -- verify directly," which is exactly what surfaced this): a bare
-- `CREATE OR REPLACE FUNCTION` that APPENDS a new parameter -- even one with a default
-- -- does NOT replace the existing function in place. Postgres identifies a function by
-- (schema, name, parameter TYPE LIST); appending a parameter changes that type list, so
-- `CREATE OR REPLACE` creates a SECOND, distinct, ambiguity-causing overload alongside
-- the original instead of replacing it (confirmed live: after a bare CREATE OR REPLACE
-- with an appended trailing default parameter, `\df` showed two rows for the same
-- function name, and every existing 6-argument call site would keep silently resolving
-- to the OLD, un-fixed overload -- exactly defeating this fix's own purpose). This
-- repository already has its own established, tested precedent for this EXACT class of
-- change: `20260730790000_harden_procurement_dashboard_reports_tier_c_review_fixes.sql`
-- (`app.list_procurement_dashboard_saved_views` / `app.list_procurement_vendor_risk_
-- dashboard_rows`, both widened by a new trailing parameter) uses `DROP FUNCTION IF
-- EXISTS <old signature>` followed by `CREATE FUNCTION` (not "or replace" -- the old
-- one is already gone) and an explicit `REVOKE ... FROM PUBLIC` + `GRANT ... TO
-- authenticated, service_role` re-statement, because a freshly CREATEd function (post
-- DROP) again carries the default PUBLIC execute grant this schema's own `ALTER
-- DEFAULT PRIVILEGES` revoke only covered for functions that existed when IT ran. The
-- two functions below that append a parameter (`app.create_procurement_approval_
-- policy_version`, `app.evaluate_procurement_approval_requirement`) follow that exact
-- precedent. The two functions below with an UNCHANGED signature (`app._request_
-- procurement_entity_approval`, and the brand-new private `app._evaluate_procurement_
-- currency_threshold`) use plain `CREATE OR REPLACE` / `CREATE`, which is correct and
-- sufficient for those. No existing migration file is edited.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. app.procurement_approval_policies.policy_currency -- the currency
--    min_value_amount is denominated in. Existing published policy rows (from
--    db-test fixtures/prior migrations) get 'USD' via the column default -- a safe
--    default only in a pre-production repository with no real tenant data (this
--    repository has none); a real production migration would need an explicit
--    backfill decision, deliberately out of this bounded fix's own scope.
-- ---------------------------------------------------------------------------

alter table app.procurement_approval_policies
  add column policy_currency text not null default 'USD';

comment on column app.procurement_approval_policies.policy_currency is
  'ISS-2026-045: the ISO 4217 currency min_value_amount is denominated in, validated by app.validate_currency_code (FIN-194''s real registry). Resolved at create time by app.create_procurement_approval_policy_version -- explicit caller value, else the tenant''s own published locale default currency, else ''USD''. Existing rows default to ''USD'' (this repository carries no real tenant data to backfill).';

alter table app.procurement_approval_policies
  add constraint procurement_approval_policies_policy_currency_check
  check (app.validate_currency_code(policy_currency));

-- ---------------------------------------------------------------------------
-- 2. app.create_procurement_approval_policy_version -- appends ONE new trailing
--    parameter p_policy_currency (default null), no reordering/removal of any
--    existing parameter. DROP + CREATE + re-GRANT (see this file's own top-of-file
--    design note on why a bare CREATE OR REPLACE does not suffice here).
-- ---------------------------------------------------------------------------

drop function if exists app.create_procurement_approval_policy_version(uuid, text, numeric, boolean, uuid, text);

create function app.create_procurement_approval_policy_version(
  p_tenant_id uuid,
  p_entity_type text,
  p_min_value_amount numeric,
  p_always_required boolean,
  p_actor_auth_user_id uuid,
  p_created_by text,
  p_policy_currency text default null
)
returns app.procurement_approval_policies
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_decision app.rbac_decision;
  v_policy app.procurement_approval_policies;
  v_currency text;
begin
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % holds no active membership for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, p_tenant_id, 'PRC', 'Create');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks PRC:Create (%) for tenant %', p_actor_auth_user_id, v_decision.reason, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if p_entity_type not in ('vendor_activation', 'rate_version', 'vendor_selection', 'purchase_order', 'vendor_contract', 'exception_override') then
    raise exception 'invalid_entity_type: % is not a governed procurement approval entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  -- ISS-2026-045: resolve the currency min_value_amount is denominated in -- explicit
  -- caller value first, then the tenant's own published locale default currency
  -- (app.tenant_locale_versions, PLT-119), then a disclosed safe 'USD' fallback. Reuses
  -- app.validate_currency_code (FIN-194's real app.finance_currencies registry) rather
  -- than inventing a second currency-code validator.
  v_currency := coalesce(
    p_policy_currency,
    (select tlv.default_currency from app.tenant_locale_versions tlv where tlv.tenant_id = p_tenant_id and tlv.status = 'published'),
    'USD'
  );
  if not app.validate_currency_code(v_currency) then
    raise exception 'invalid_currency_code: % is not a registered, active currency', v_currency
      using errcode = 'check_violation';
  end if;

  insert into app.procurement_approval_policies (tenant_id, entity_type, min_value_amount, always_required, policy_currency, created_by)
  values (p_tenant_id, p_entity_type, p_min_value_amount, coalesce(p_always_required, false), v_currency, p_created_by)
  returning * into v_policy;

  perform app.capture_audit_event(
    p_tenant_id, p_actor_auth_user_id, p_created_by, 'create_procurement_approval_policy_version',
    'app.procurement_approval_policies', v_policy.id, 'success', null, null, to_jsonb(v_policy)
  );

  return v_policy;
end;
$$;

comment on function app.create_procurement_approval_policy_version is
  'PRC-259: creates a new draft threshold policy version. ISS-2026-045 (Prompt 269): now resolves and validates policy_currency (explicit p_policy_currency, else the tenant''s own published locale default currency, else USD) -- the currency min_value_amount is denominated in, closing the currency-blind threshold comparison.';

-- ERR-2026-004 / this file's own DROP+CREATE precedent (see top-of-file design note):
-- a freshly CREATEd function grants EXECUTE to PUBLIC by default, undoing the original
-- migration's own blanket revoke (which only covered functions that existed at the
-- time IT ran). Revoke PUBLIC explicitly before re-granting, exactly as
-- 20260730790000 already established for this identical class of change.
revoke execute on function app.create_procurement_approval_policy_version(uuid, text, numeric, boolean, uuid, text, text) from public;
grant execute on function app.create_procurement_approval_policy_version(uuid, text, numeric, boolean, uuid, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. app._evaluate_procurement_currency_threshold -- private (no grant, callable
--    only from within another SECURITY DEFINER function owned by the same role,
--    mirrors app._normalize_vendor_comparison_currency, PRC-258 -- but a DELIBERATE,
--    DISCLOSED VARIANT, not an identical copy, per the design note at the top of
--    this file). Called only from app.evaluate_procurement_approval_requirement below.
-- ---------------------------------------------------------------------------

create function app._evaluate_procurement_currency_threshold(
  p_tenant_id uuid,
  p_source_amount numeric,
  p_source_currency text,
  p_target_currency text,
  p_actor_auth_user_id uuid
)
returns table (normalized_amount numeric, ok boolean, failure_code text)
language plpgsql
as $$
declare
  v_result jsonb;
begin
  begin
    v_result := app.convert_finance_amount(p_tenant_id, p_source_amount, p_source_currency, p_target_currency, 'spot', now(), p_actor_auth_user_id);
  exception
    -- Same "discriminate before recovering" discipline (taxonomy C-09) PRC-258's own
    -- precedent already established: verify the SQLERRM prefix before treating a
    -- caught condition as the expected outcome, re-raising anything else (e.g. a
    -- genuinely corrupted finance_rounding config surfacing as check_violation deep
    -- inside app.apply_finance_rounding, which must NOT be mischaracterized as
    -- "unsupported currency").
    when no_data_found then
      if sqlerrm not like 'finance_exchange_rate_missing:%' then
        raise;
      end if;
      return query select null::numeric, false, 'fx_rate_missing';
      return;
    when check_violation then
      if sqlerrm not like 'finance_exchange_rate_unsupported_currency:%' then
        raise;
      end if;
      return query select null::numeric, false, 'fx_conversion_invalid';
      return;
    -- THE DELIBERATE VARIANT (ISS-2026-045, see this file's own top-of-file design
    -- note): PRC-258's own precedent lets insufficient_privilege propagate uncaught
    -- because its caller already proactively checks FIN:View before ever reaching this
    -- helper. This evaluator's own actor gate is deliberately has_active_tenant_
    -- membership only (see the design note preserved in app.evaluate_procurement_
    -- approval_requirement below) -- a caller legitimately authorized to create a
    -- rate/PO/selection by an unrelated authority model (e.g. app.create_rate_
    -- version's own app.is_support_grant_authority) may hold no FIN:View at all. Let
    -- app.convert_finance_amount's own insufficient_privilege abort the ENTIRE submit
    -- transaction here would be a far worse regression than the governance question
    -- itself -- so it is caught and folded into the SAME "conversion unavailable"
    -- outcome as a missing rate or unsupported currency, and the caller below FAILS
    -- CLOSED (required=true) rather than silently skipping governance. Do not "fix"
    -- this back to letting insufficient_privilege propagate -- that would re-open the
    -- exact worse regression this variant exists to prevent.
    when insufficient_privilege then
      if sqlerrm not like 'insufficient_authority:%lacks FIN:View%' then
        raise;
      end if;
      return query select null::numeric, false, 'fx_authority_unavailable';
      return;
  end;
  return query select (v_result ->> 'convertedAmount')::numeric, true, null::text;
end;
$$;

comment on function app._evaluate_procurement_currency_threshold is
  'ISS-2026-045 (Prompt 269): a DELIBERATE, DISCLOSED VARIANT of app._normalize_vendor_comparison_currency (PRC-258) -- the ONE call site for app.convert_finance_amount composition inside the procurement approval threshold evaluator. Narrowly catches no_data_found (missing FX rate), check_violation (unsupported currency), AND insufficient_privilege (actor lacks FIN:View -- unlike the PRC-258 precedent, which lets this propagate because its own caller pre-checks FIN:View; this evaluator''s caller deliberately does not, see app.evaluate_procurement_approval_requirement''s own design note). All three degrade to a structured "conversion unavailable" failure, never an aborted transaction. The caller fails CLOSED (required=true) on any of the three -- under-routing a large foreign-currency value is the more dangerous direction (ISS-2026-045).';

-- ---------------------------------------------------------------------------
-- 4. app.evaluate_procurement_approval_requirement -- CURRENT (670000-amended) body,
--    assert_actor_is_session_identity call and the tenant-membership/customer-layer
--    gate preserved unchanged. Appends ONE new trailing parameter p_value_currency
--    (default null). Only the threshold comparison block otherwise changes. DROP +
--    CREATE + re-GRANT (see this file's own top-of-file design note).
-- ---------------------------------------------------------------------------

drop function if exists app.evaluate_procurement_approval_requirement(text, uuid, numeric, uuid);

create function app.evaluate_procurement_approval_requirement(
  p_entity_type text,
  p_tenant_id uuid,
  p_value_amount numeric,
  p_actor_auth_user_id uuid,
  p_value_currency text default null
)
returns table (required boolean, reasons text[], policy_version_id uuid)
language plpgsql
stable
security definer
set search_path = app, pg_temp
as $$
declare
  v_policy app.procurement_approval_policies;
  v_reasons text[] := array[]::text[];
  v_norm_amount numeric;
  v_norm_ok boolean;
  v_norm_failure text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  if p_entity_type not in ('vendor_activation', 'rate_version', 'vendor_selection', 'purchase_order', 'vendor_contract', 'exception_override') then
    raise exception 'invalid_entity_type: % is not a governed procurement approval entity type', p_entity_type
      using errcode = 'check_violation';
  end if;

  -- Deliberately app.has_active_tenant_membership, NOT a specific PRC:* permission --
  -- app.procurement_approval_policies itself is directly readable by any active tenant
  -- member (this migration's own RLS policy below, mirroring app.quotation_approval_
  -- rules' own "tenant-wide reference data, never field-masked" posture, COM-153); a
  -- stricter gate here would protect nothing a raw select on that same table does not
  -- already expose, while wrongly blocking a legitimately authorized caller whose own
  -- authority model is not the PRC permission catalogue at all (app.create_rate_
  -- version's own app.is_support_grant_authority, COM-149, unchanged by PRC-255 --
  -- caught live by this checkpoint's own full db:test run against advanced-tms-
  -- canonical-telemetry-arbitration.sql, not merely reasoned about). ISS-2026-045
  -- (Prompt 269): this is EXACTLY why app._evaluate_procurement_currency_threshold
  -- below must also catch insufficient_privilege rather than let it propagate -- a
  -- caller reachable here may legitimately hold no FIN:View at all.
  if not app.has_active_tenant_membership(p_tenant_id, p_actor_auth_user_id) or app.actor_holds_customer_user_layer(p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % is not an active member of tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_policy from app.procurement_approval_policies where tenant_id = p_tenant_id and entity_type = p_entity_type and status = 'published';
  if not found then
    return query select false, array[]::text[], null::uuid;
    return;
  end if;

  if v_policy.always_required then
    v_reasons := array_append(v_reasons, 'always_required');
  end if;

  -- ISS-2026-045 (Prompt 269): currency-aware threshold comparison. min_value_amount
  -- can only ever be set for rate_version/vendor_selection/purchase_order (the
  -- pre-existing, untouched procurement_approval_policies_value_dimension_check CHECK
  -- constraint) -- vendor_activation/vendor_contract/exception_override structurally
  -- never enter this branch at all.
  if v_policy.min_value_amount is not null and p_value_amount is not null then
    if p_value_currency is null or p_value_currency = v_policy.policy_currency then
      -- Same-currency (or no currency supplied -- the legacy pre-this-fix call shape,
      -- unchanged behavior): compare directly, exactly as before this fix.
      if p_value_amount >= v_policy.min_value_amount then
        v_reasons := array_append(v_reasons, 'value_meets_threshold');
      end if;
    else
      select t.normalized_amount, t.ok, t.failure_code
      into v_norm_amount, v_norm_ok, v_norm_failure
      from app._evaluate_procurement_currency_threshold(p_tenant_id, p_value_amount, p_value_currency, v_policy.policy_currency, p_actor_auth_user_id) t;

      if v_norm_ok then
        if v_norm_amount >= v_policy.min_value_amount then
          v_reasons := array_append(v_reasons, 'value_meets_threshold');
        end if;
      else
        -- FAIL CLOSED (ISS-2026-045): conversion unavailable (missing FX rate,
        -- unsupported currency, or the actor lacks FIN:View) -- treat the threshold as
        -- met rather than silently skip governance. Under-routing (a large
        -- foreign-currency value silently skipping a review it should have triggered)
        -- is the more dangerous direction than over-routing. Do not "fix" this back to
        -- required=false -- see this file's own top-of-file design note.
        v_reasons := array_append(v_reasons, 'value_currency_unverifiable_defaulted_to_required');
      end if;
    end if;
  end if;

  return query select (array_length(v_reasons, 1) is not null), v_reasons, v_policy.id;
end;
$$;

comment on function app.evaluate_procurement_approval_requirement is
  'PRC-259: the one deterministic, explainable "does this procurement decision need approval" evaluator, shared by every governed entity_type. A tenant with no published policy for that entity_type skips routing entirely (opt-in, mirrors COM-153''s own quotation precedent) -- required=false, no reasons, policy_version_id=null. Batch 257-259 review (C-13, HIGH): asserts caller-is-actor first. ISS-2026-045 (Prompt 269, HIGH): the threshold comparison is now currency-aware -- p_value_currency matching v_policy.policy_currency (or omitted, the legacy shape) compares directly, unchanged; a genuine mismatch normalizes via app._evaluate_procurement_currency_threshold and FAILS CLOSED (required=true, reason value_currency_unverifiable_defaulted_to_required) on any conversion-unavailable outcome rather than silently skipping governance.';

-- ERR-2026-004 / this file's own DROP+CREATE precedent (see top-of-file design note):
-- a freshly CREATEd function grants EXECUTE to PUBLIC by default. Revoke PUBLIC
-- explicitly before re-granting, exactly as 20260730790000 already established for
-- this identical class of change.
revoke execute on function app.evaluate_procurement_approval_requirement(text, uuid, numeric, uuid, text) from public;
grant execute on function app.evaluate_procurement_approval_requirement(text, uuid, numeric, uuid, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. app._request_procurement_entity_approval -- SAME signature (already carries
--    p_currency from every one of its 5 call sites). Body-only change: thread
--    p_currency as the new 5th positional argument into its own call to
--    app.evaluate_procurement_approval_requirement.
-- ---------------------------------------------------------------------------

create or replace function app._request_procurement_entity_approval(
  p_entity_type text,
  p_tenant_id uuid,
  p_entity_id uuid,
  p_value_amount numeric,
  p_currency text,
  p_context jsonb,
  p_source_record_version integer,
  p_idempotency_key text,
  p_actor_auth_user_id uuid,
  p_actor_label text,
  out required boolean,
  out approval_status text,
  out approval_request_id uuid,
  out policy_version_id uuid
)
language plpgsql
as $$
declare
  v_reasons text[];
  v_config_version_id uuid;
  v_request app.approval_requests;
  v_existing_snapshot app.procurement_approval_context_snapshots;
begin
  -- ISS-2026-045 (Prompt 269): p_currency is now threaded through as the 5th
  -- positional argument -- previously only ever used below to populate the context
  -- snapshot's own currency column, never fed into the threshold comparison itself.
  select e.required, e.reasons, e.policy_version_id into required, v_reasons, policy_version_id
  from app.evaluate_procurement_approval_requirement(p_entity_type, p_tenant_id, p_value_amount, p_actor_auth_user_id, p_currency) e;

  if not required then
    approval_status := 'not_required';
    approval_request_id := null;
    return;
  end if;

  select cv.id into v_config_version_id
  from app.config_versions cv
  join app.config_objects co on co.id = cv.config_object_id
  where co.config_type_code = 'approval' and co.tenant_id = p_tenant_id and co.scope_level = 'tenant' and cv.status = 'published';

  if v_config_version_id is null then
    raise exception 'approval_definition_not_configured: tenant % crossed a procurement approval threshold for % but has no published approval routing definition', p_tenant_id, p_entity_type
      using errcode = 'check_violation';
  end if;

  select * into v_request from app.request_approval(
    v_config_version_id, p_tenant_id, p_entity_type, p_entity_id, p_idempotency_key, p_actor_auth_user_id, p_actor_label
  );

  approval_status := 'pending';
  approval_request_id := v_request.id;

  -- app.request_approval's own (tenant_id, idempotency_key) short-circuit already
  -- returns the SAME existing request row on a genuine replay (taxonomy C-01, handled
  -- once, upstream, not re-implemented here) -- only insert a context snapshot the
  -- first time this exact request is created.
  select * into v_existing_snapshot from app.procurement_approval_context_snapshots s where s.approval_request_id = v_request.id;
  if not found then
    insert into app.procurement_approval_context_snapshots (
      approval_request_id, tenant_id, entity_type, entity_id, value_amount, currency,
      reasons, policy_version_id, context, source_record_version, created_by
    ) values (
      v_request.id, p_tenant_id, p_entity_type, p_entity_id, p_value_amount, p_currency,
      v_reasons, policy_version_id, coalesce(p_context, '{}'::jsonb), p_source_record_version, p_actor_label
    );
  end if;
end;
$$;

comment on function app._request_procurement_entity_approval is
  'PRC-259: private submit-time glue, no grant -- called once from inside each governed entity''s own SECURITY DEFINER submit/transition RPC (nested calls execute with the caller''s own definer rights, the same established PRC-257/258 precedent). Never called directly by the TypeScript service layer. ISS-2026-045 (Prompt 269): now threads its own p_currency into app.evaluate_procurement_approval_requirement, closing the currency-blind threshold comparison.';

-- Per ERR-2026-004 (docs/runtime/ERROR_LEDGER.md): explicit, directly-provable revoke of
-- PostgreSQL's PUBLIC-execute default, the standing per-migration convention since
-- PLT-118 -- REQUIRED here because this migration creates one genuinely NEW function
-- (app._evaluate_procurement_currency_threshold), which would otherwise silently carry
-- the implicit PUBLIC grant every freshly CREATEd function receives (the same class of
-- gap ERR-2026-004 itself registers). Verified live, not assumed: without this
-- statement, `has_function_privilege('authenticated', ..., 'EXECUTE')` on the new
-- function returned true. The two DROP+CREATEd functions above already carry their own
-- explicit single-function REVOKE+GRANT pairs (Postgres privilege grants are additive,
-- independent per-role ACL entries -- this blanket PUBLIC revoke does not touch either
-- of those specific `authenticated`/`service_role` grants).
revoke execute on all functions in schema app from public;
