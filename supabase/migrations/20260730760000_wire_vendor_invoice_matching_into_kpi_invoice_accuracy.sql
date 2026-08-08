-- Corrective migration for Procurement capability PRC-265 (Vendor Invoice Matching,
-- CG-S11-PRC-016). Wires the real evidence source this prompt built
-- (app.vendor_bill_match_cases, 20260730750000_create_procurement_vendor_invoice_
-- matching.sql) into the `invoice_accuracy` vendor KPI category PRC-264 built
-- structurally present but deliberately never computed (design note 2 of
-- 20260730740000_create_procurement_vendor_performance.sql -- an ALREADY-APPLIED,
-- already-committed migration, never edited directly; this file is a NEW migration per
-- AGENTS.md's protected-path rule).
--
-- ===========================================================================
-- The decision this migration makes, and why (per the task's own instruction: this must
-- be a real, disclosed decision, not silently ignored either way)
-- ===========================================================================
--
-- PRC-264's own `app._calc_vendor_kpi_invoice_accuracy()` took ZERO arguments and
-- returned a hardcoded `is_computable=false` result unconditionally -- by design, since
-- its real evidence source (this prompt) did not exist yet. Now that
-- `app.vendor_bill_match_cases` is real, genuine, tenant-scoped match-case evidence,
-- the honest choice is to WIRE it, not leave the calculator permanently inert. This
-- migration:
--
-- 1. `DROP FUNCTION app._calc_vendor_kpi_invoice_accuracy()` (the 0-argument form) and
--    `CREATE FUNCTION app._calc_vendor_kpi_invoice_accuracy(p_tenant_id uuid,
--    p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)` --
--    a genuine signature change (0 args -> 4 args), so DROP+CREATE per AGENTS.md, not
--    CREATE OR REPLACE. The dropped function was internal-only with NO grant of its own
--    (PRC-264's own migration header: "internal only -- no grant, dispatched exclusively
--    by app._calculate_vendor_kpi_metric_value") -- confirmed by direct inspection of
--    20260730740000's own grant block before this migration was written -- so there is
--    no grant to re-issue.
-- 2. `CREATE OR REPLACE FUNCTION app._calculate_vendor_kpi_metric_value(...)` -- SAME
--    signature as PRC-264 already committed, only the one `invoice_accuracy` case
--    branch changes (from a bare call to one now threading the four real parameters
--    through). This function is also internal-only with no grant of its own (same
--    header), so CREATE OR REPLACE is safe and needs no re-grant either.
--
-- Computation: denominator = every CURRENT match case for this vendor whose own
-- evaluated_at falls in the window and whose overall_status has reached a real
-- decision (matched/exception/blocked/disputed -- i.e. NOT still pending, which means
-- "not yet decided," the same "only count what has actually happened" discipline every
-- sibling calculator already uses for its own denominator). numerator = cases that
-- reached overall_status = 'matched' WITHOUT ever needing an exception approval (a
-- clean match within tolerance, or an explicitly accepted one) -- a case that needed
-- exception approval, even if eventually approved, genuinely WAS inaccurate at
-- submission time, which is exactly what this KPI measures. Excludes any case carrying
-- an UPHELD dispute against it via the SAME generic `app.vendor_kpi_source_disputes`
-- mechanism (kpi_code='invoice_accuracy', source_id=match_case.id) every other
-- calculator already uses -- no new dispute infrastructure needed; this table already
-- exists and is already keyed generically by (kpi_code, source_id).
--
-- This does NOT retroactively change any tenant's own already-published
-- `vendor_kpi_definitions` row for `invoice_accuracy` -- `is_computable` lives on that
-- PER-TENANT, VERSIONED catalogue row (set by the tenant's own
-- `create_vendor_kpi_definition_draft`/`publish_vendor_kpi_definition` calls), not on
-- the calculator itself. `app.calculate_vendor_kpi_metrics` (PRC-264, unmodified) only
-- ever calls this calculator when `v_definition.is_computable = true` for that tenant's
-- own currently-published definition row -- confirmed by direct inspection of
-- 20260730740000's own dispatch loop before writing this migration. A tenant whose
-- existing `invoice_accuracy` definition was published with `is_computable=false`
-- (PRC-264's own disclosed default) stays exactly as it was until that tenant
-- publishes a NEW version with `is_computable=true` -- an ordinary, expected use of the
-- versioning model this capability already has, not a gap this migration needs to
-- backfill. This is the honest, bounded scope of "wiring the real source": the
-- calculator can now genuinely compute a real value; whether and when a given tenant
-- turns it on is that tenant's own governed decision, unchanged.

drop function if exists app._calc_vendor_kpi_invoice_accuracy();

create function app._calc_vendor_kpi_invoice_accuracy(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
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
    count(*) filter (where mc.overall_status = 'matched'),
    count(*),
    array_agg(mc.id)
  into v_num, v_den, v_ids
  from app.vendor_bill_match_cases mc
  where mc.tenant_id = p_tenant_id and mc.vendor_master_id = p_vendor_master_id and mc.is_current
    and mc.overall_status in ('matched', 'exception', 'blocked', 'disputed')
    and mc.evaluated_at >= p_window_start and mc.evaluated_at < p_window_end
    and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'invoice_accuracy' and d.source_id = mc.id and d.status = 'upheld');

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when not r.is_computable then 'no_evaluated_bills: no vendor bill match case for this vendor reached a decided outcome in the window' else null end;
  r.source_evidence := jsonb_build_object('evaluated', coalesce(v_den, 0), 'matched_clean', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_invoice_accuracy is
  'PRC-265 wiring (was PRC-264''s permanent is_computable=false stub, 0-argument form -- see this migration''s own header for the DROP+CREATE reasoning). Denominator: current match cases (app.vendor_bill_match_cases, PRC-265) for this vendor that reached a real decided outcome (matched/exception/blocked/disputed, never still-pending) with evaluated_at in the window. Numerator: cases that reached matched -- a clean within-tolerance or explicitly-accepted match; a case that needed exception approval, even if later approved, genuinely was inaccurate and does not count. Excludes any case with an UPHELD app.vendor_kpi_source_disputes row (kpi_code=''invoice_accuracy''), the same generic exclusion mechanism every sibling calculator already uses.';

create or replace function app._calculate_vendor_kpi_metric_value(
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
    when 'invoice_accuracy' then r := app._calc_vendor_kpi_invoice_accuracy(p_tenant_id, p_vendor_master_id, p_window_start, p_window_end);
    else
      raise exception 'invalid_kpi_code: % is not a supported KPI category', p_kpi_code using errcode = 'check_violation';
  end case;
  return r;
end;
$$;

comment on function app._calculate_vendor_kpi_metric_value is
  'PRC-264, widened by PRC-265 to thread real parameters into invoice_accuracy (was a bare call to a 0-argument stub). The one dispatch point routing a kpi_code to its fixed built-in calculator. Internal only -- no grant; app.calculate_vendor_kpi_metrics is the sole authorized caller. Signature unchanged from PRC-264''s own original -- CREATE OR REPLACE is safe, no re-grant needed (confirmed: this function carries no grant of its own in 20260730740000).';

-- Taxonomy C-11: a brand-new `CREATE FUNCTION` (the DROP+CREATE 4-argument
-- app._calc_vendor_kpi_invoice_accuracy above) is granted EXECUTE to PUBLIC by
-- PostgreSQL's own default unless explicitly revoked -- the identical per-migration
-- convention (ERR-2026-004, PLT-118) every other migration in this repository already
-- follows, re-applied here because a DROP genuinely removes the prior function (and
-- its prior revoke) from existence, not merely REPLACEs its body.
revoke execute on all functions in schema app from public;
