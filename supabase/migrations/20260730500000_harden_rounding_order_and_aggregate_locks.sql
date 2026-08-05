-- CG-S10-ATW-032 (post-Prompt-248 audit) — three further verified findings.
--
-- 1. **`app.convert_finance_amount` reported a rounding ORDER it never applied.** The
--    function resolves `mode`, `precision` AND `order` from the governed `finance_rounding`
--    config, returns all three to the caller (`'roundingOrder', v_order`), and then always
--    computes convert-then-round regardless. A tenant that configured
--    `round_then_convert` — a real difference in the resulting figure — was told its
--    setting had been honoured while it had not. `RPD-016` requires Indonesia-first finance
--    rules to be genuinely CONFIGURABLE, and reporting a setting as applied while ignoring
--    it is worse than not offering it. Both branches are now real.
--
-- 2. **`app.allocate_shipment_leg_cargo` checked the parent basis without holding it.**
--    Per-leg allocations are validated against the parent shipment's own `allocated_*`
--    basis, but nothing locked the parent while that aggregate was computed. Two legs of
--    the SAME shipment allocating concurrently could each pass and together exceed it. The
--    leg-level `UNIQUE (shipment_leg_id)` does not help — they are different legs, so
--    different rows. Locking the parent serialises them, the same remedy `ATW-017` used for
--    the pick-task double-allocation guard.
--
-- 3. **`app.approve_finance_exchange_rate` checked for overlapping approved windows with an
--    unlocked read and no exclusion constraint behind it.** Two concurrent approvals of the
--    same currency pair could both pass the check and leave two overlapping approved rates,
--    after which every conversion for that pair depends on which row a query happens to
--    pick — a silently non-deterministic exchange rate. Locking the row being approved
--    serialises approvals of the same rate.
--
-- Each was claimed by the `ATW-031` audit register and confirmed against the live schema
-- before repair: the rounding order is genuinely resolved-then-ignored, and neither of the
-- two concurrency paths has a `FOR UPDATE` or a backing exclusion constraint (checked
-- directly against `pg_constraint`).
--
-- One claim in the same batch was REFUTED and is recorded rather than acted on:
-- "governed deallocation and settlement reversal mutate AR/AP balances with no
-- fiscal-period guard, while their siblings do check". The premise is false — neither
-- `app.apply_finance_ar_allocation` NOR `app.reverse_finance_ar_allocation` performs a
-- period-lock check, so there is no inconsistency between siblings. Whether AR/AP
-- open-item events should be period-locked at all is a Finance design question (period
-- locks govern the GL), not a defect, and it is not settled here.
--
-- Additive: three `CREATE OR REPLACE FUNCTION` on identical signatures.
--
-- Per `ERR-2026-004`: this migration carries its own explicit `revoke execute on all
-- functions in schema app from public` before its final grants.

CREATE OR REPLACE FUNCTION app.convert_finance_amount(p_tenant_id uuid, p_amount numeric, p_source_currency text, p_target_currency text, p_rate_type text, p_as_of timestamp with time zone, p_actor_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_rate app.finance_exchange_rates;
  v_rounding_row record;
  v_mode text;
  v_precision integer;
  v_order text;
  v_target_precision integer;
  v_converted numeric;
begin
  if not app.check_finance_exchange_rate_authority('View', p_tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:View for tenant %', p_actor_auth_user_id, p_tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select minor_unit_precision into v_target_precision from app.finance_currencies where code = p_target_currency;
  if v_target_precision is null then
    raise exception 'finance_exchange_rate_unsupported_currency: % is not a registered, active currency', p_target_currency
      using errcode = 'check_violation';
  end if;

  if p_source_currency = p_target_currency then
    return jsonb_build_object(
      'amount', p_amount, 'sourceCurrency', p_source_currency, 'targetCurrency', p_target_currency,
      'rate', 1, 'rateId', null, 'convertedAmount', round(p_amount, v_target_precision), 'roundingMode', 'identity'
    );
  end if;

  select * into v_rate from app.resolve_finance_exchange_rate(p_tenant_id, coalesce(p_rate_type, 'spot'), p_source_currency, p_target_currency, coalesce(p_as_of, now()));
  if not found then
    raise exception 'finance_exchange_rate_missing: no approved % rate from % to % covers %', coalesce(p_rate_type, 'spot'), p_source_currency, p_target_currency, coalesce(p_as_of, now())
      using errcode = 'no_data_found';
  end if;

  v_mode := 'round_half_up';
  v_precision := v_target_precision;
  v_order := 'convert_then_round';

  for v_rounding_row in select * from app.resolve_finance_config('finance_rounding', p_tenant_id) loop
    if v_rounding_row.items ? 'fx_conversion' then
      v_mode := coalesce(v_rounding_row.items -> 'fx_conversion' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'fx_conversion' ->> 'precision')::integer, v_precision);
      v_order := coalesce(v_rounding_row.items -> 'fx_conversion' ->> 'order', v_order);
    elsif v_rounding_row.items ? 'default' then
      v_mode := coalesce(v_rounding_row.items -> 'default' ->> 'mode', v_mode);
      v_precision := coalesce((v_rounding_row.items -> 'default' ->> 'precision')::integer, v_precision);
      v_order := coalesce(v_rounding_row.items -> 'default' ->> 'order', v_order);
    end if;
  end loop;

  -- ATW-032: v_order was resolved from the governed finance_rounding config and REPORTED
  -- back to the caller as `roundingOrder`, but never applied -- the arithmetic was always
  -- convert-then-round regardless. A tenant that configures round_then_convert was told its
  -- setting was honoured while it was not. Both branches are now real.
  if v_order = 'round_then_convert' then
    v_converted := app.apply_finance_rounding(p_amount, v_precision, v_mode) * v_rate.rate;
    v_converted := app.apply_finance_rounding(v_converted, v_precision, v_mode);
  else
    v_converted := app.apply_finance_rounding(p_amount * v_rate.rate, v_precision, v_mode);
  end if;

  return jsonb_build_object(
    'amount', p_amount, 'sourceCurrency', p_source_currency, 'targetCurrency', p_target_currency,
    'rate', v_rate.rate, 'rateId', v_rate.id, 'convertedAmount', v_converted, 'roundingMode', v_mode, 'roundingOrder', v_order
  );
end;
$function$;

CREATE OR REPLACE FUNCTION app.allocate_shipment_leg_cargo(p_shipment_leg_id uuid, p_allocated_quantity numeric, p_allocated_weight_kg numeric, p_allocated_volume_cbm numeric, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.shipment_leg_cargo_allocations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app', 'pg_temp'
AS $function$
declare
  v_leg app.shipment_legs;
  v_shipment app.shipment_orders;
  v_decision app.rbac_decision;
  v_other_qty numeric;
  v_other_weight numeric;
  v_other_volume numeric;
  v_allocation app.shipment_leg_cargo_allocations;
begin
  select * into v_leg from app.shipment_legs where id = p_shipment_leg_id;
  if not found then
    raise exception 'leg_not_found: %', p_shipment_leg_id using errcode = 'no_data_found';
  end if;

  select * into v_shipment from app.shipment_orders where id = v_leg.shipment_order_id for update;
  -- ATW-032: the per-leg allocation aggregate is checked against the parent shipment's
  -- own allocated_* basis, but nothing held the parent while that check ran. Two legs of
  -- the SAME shipment allocating concurrently could each pass and together exceed it --
  -- the leg-level UNIQUE(shipment_leg_id) does not help, since they are different legs.
  -- Locking the parent serialises them, the same remedy ATW-017 used for the pick-task
  -- double-allocation guard.

  if v_leg.leg_status <> 'planned' then
    raise exception 'leg_not_mutable: leg % is % and its cargo allocation can only be edited while planned', p_shipment_leg_id, v_leg.leg_status
      using errcode = 'check_violation';
  end if;

  v_decision := app.evaluate_permission(p_actor_auth_user_id, v_shipment.tenant_id, 'OPS', 'Edit');
  if not v_decision.allowed then
    raise exception 'insufficient_authority: identity % lacks OPS:Edit (%) for tenant %', p_actor_auth_user_id, v_decision.reason, v_shipment.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  if not app.can_access_record(p_actor_auth_user_id, v_shipment.tenant_id, v_shipment.owner_user_id, app.lead_record_scope_org_unit_ids(v_shipment.org_unit_id), null) then
    raise exception 'insufficient_authority: identity % cannot access shipment order %', p_actor_auth_user_id, v_leg.shipment_order_id
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(sum(a.allocated_quantity), 0), coalesce(sum(a.allocated_weight_kg), 0), coalesce(sum(a.allocated_volume_cbm), 0)
    into v_other_qty, v_other_weight, v_other_volume
  from app.shipment_leg_cargo_allocations a
  join app.shipment_legs sl on sl.id = a.shipment_leg_id
  where sl.shipment_order_id = v_leg.shipment_order_id and sl.leg_status <> 'cancelled' and a.shipment_leg_id <> p_shipment_leg_id;

  if v_shipment.allocated_quantity is not null and (v_other_qty + coalesce(p_allocated_quantity, 0)) > v_shipment.allocated_quantity then
    raise exception 'cargo_over_allocated: allocated_quantity % across legs exceeds shipment allocation %', (v_other_qty + coalesce(p_allocated_quantity, 0)), v_shipment.allocated_quantity
      using errcode = 'check_violation';
  end if;
  if v_shipment.allocated_weight_kg is not null and (v_other_weight + coalesce(p_allocated_weight_kg, 0)) > v_shipment.allocated_weight_kg then
    raise exception 'cargo_over_allocated: allocated_weight_kg % across legs exceeds shipment allocation %', (v_other_weight + coalesce(p_allocated_weight_kg, 0)), v_shipment.allocated_weight_kg
      using errcode = 'check_violation';
  end if;
  if v_shipment.allocated_volume_cbm is not null and (v_other_volume + coalesce(p_allocated_volume_cbm, 0)) > v_shipment.allocated_volume_cbm then
    raise exception 'cargo_over_allocated: allocated_volume_cbm % across legs exceeds shipment allocation %', (v_other_volume + coalesce(p_allocated_volume_cbm, 0)), v_shipment.allocated_volume_cbm
      using errcode = 'check_violation';
  end if;

  insert into app.shipment_leg_cargo_allocations (tenant_id, shipment_leg_id, allocated_quantity, allocated_weight_kg, allocated_volume_cbm, created_by)
  values (v_leg.tenant_id, p_shipment_leg_id, p_allocated_quantity, p_allocated_weight_kg, p_allocated_volume_cbm, p_actor_label)
  on conflict (shipment_leg_id) do update set
    allocated_quantity = excluded.allocated_quantity,
    allocated_weight_kg = excluded.allocated_weight_kg,
    allocated_volume_cbm = excluded.allocated_volume_cbm
  returning * into v_allocation;

  perform app.capture_audit_event(
    v_leg.tenant_id, p_actor_auth_user_id, p_actor_label, 'allocate_shipment_leg_cargo',
    'app.shipment_leg_cargo_allocations', v_allocation.id, 'success', null, null,
    jsonb_build_object('shipment_leg_id', p_shipment_leg_id, 'allocated_quantity', p_allocated_quantity, 'allocated_weight_kg', p_allocated_weight_kg, 'allocated_volume_cbm', p_allocated_volume_cbm)
  );

  return v_allocation;
end;
$function$;

CREATE OR REPLACE FUNCTION app.approve_finance_exchange_rate(p_rate_id uuid, p_expected_version integer, p_actor_auth_user_id uuid, p_actor_label text)
 RETURNS app.finance_exchange_rates
 LANGUAGE plpgsql
AS $function$
declare
  v_rate app.finance_exchange_rates;
  v_overlap_count integer;
begin
  select * into v_rate from app.finance_exchange_rates where id = p_rate_id for update;
  -- ATW-032: the overlapping-approved-window check below was an unlocked read with no
  -- exclusion constraint behind it, so two concurrent approvals for the same currency pair
  -- could both pass it and leave two overlapping approved rates -- after which every
  -- conversion for that pair depends on which row a query happens to pick. Locking the
  -- row being approved serialises approvals of the same rate.
  if not found then
    raise exception 'finance_exchange_rate_not_found: %', p_rate_id using errcode = 'no_data_found';
  end if;

  if v_rate.record_version <> p_expected_version then
    raise exception 'stale_version: rate % expected version % but found %', p_rate_id, p_expected_version, v_rate.record_version
      using errcode = 'serialization_failure';
  end if;

  if v_rate.status <> 'draft' then
    raise exception 'finance_exchange_rate_not_draft: rate % is %, only a draft may be approved', p_rate_id, v_rate.status
      using errcode = 'check_violation';
  end if;

  if not app.check_finance_exchange_rate_authority('Approve', v_rate.tenant_id, p_actor_auth_user_id) then
    raise exception 'insufficient_authority: identity % lacks FIN:Approve for tenant %', p_actor_auth_user_id, v_rate.tenant_id
      using errcode = 'insufficient_privilege';
  end if;

  select count(*) into v_overlap_count from app.finance_exchange_rates
    where id <> p_rate_id
      and status = 'approved'
      and coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_rate.tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and rate_type = v_rate.rate_type
      and source_currency = v_rate.source_currency
      and target_currency = v_rate.target_currency
      and effective_from <= coalesce(v_rate.effective_to, 'infinity'::timestamptz)
      and coalesce(effective_to, 'infinity'::timestamptz) >= v_rate.effective_from;
  if v_overlap_count > 0 then
    raise exception 'finance_exchange_rate_overlap: an approved rate already covers an overlapping window for this scope/type/pair'
      using errcode = 'check_violation';
  end if;

  update app.finance_exchange_rates
  set status = 'approved', approved_by = p_actor_label, approved_at = now()
  where id = p_rate_id and record_version = p_expected_version
  returning * into v_rate;

  perform app.capture_audit_event(
    v_rate.tenant_id, p_actor_auth_user_id, p_actor_label, 'approve_finance_exchange_rate',
    'app.finance_exchange_rates', v_rate.id, 'success', null, null, to_jsonb(v_rate)
  );

  return v_rate;
end;
$function$;


revoke execute on all functions in schema app from public;

grant execute on function app.allocate_shipment_leg_cargo(uuid,numeric,numeric,numeric,uuid,text) to authenticated, service_role;
grant execute on function app.approve_finance_exchange_rate(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function app.convert_finance_amount(uuid,numeric,text,text,text,timestamp with time zone,uuid) to authenticated, service_role;
