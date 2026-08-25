-- RGL-BLK-004 (Step 16, CG-S16-RGL-004, Defect Triage): app._calc_vendor_kpi_rate_validity
-- (PRC-264, 20260730740000_create_procurement_vendor_performance.sql:1186) returns
-- is_computable = false for ANY sub-24-hour window whose date arithmetic collapses,
-- contradicting its own documented guarantee ("is_computable is true whenever the window
-- itself is non-empty -- window_days is always > 0").
--
-- Root cause, confirmed empirically (scripts/db-tests/procurement-vendor-performance.sql,
-- see the deterministic reproduction added by this same checkpoint below): the days-in-
-- window series was built as
--
--   generate_series(p_window_start::date, (p_window_end - interval '1 day')::date, interval '1 day')
--
-- The `- interval '1 day'` step is correct ONLY for a window whose length is a whole
-- number of 24-hour periods aligned so that window_end sits exactly at a day boundary
-- (e.g. [Aug1 00:00, Aug3 00:00), which correctly touches Aug1/Aug2, never Aug3, the
-- exclusive end). For any other window shape, subtracting a flat 24 hours from
-- window_end can walk its date BEFORE window_start's own date -- e.g. window
-- [Jan15 01:00, Jan15 22:00) (21 hours, same calendar day): window_start::date is
-- Jan15, but (window_end - 1 day)::date is Jan14, so generate_series(Jan15, Jan14, ...)
-- is empty. v_den collapses to 0, is_computable becomes false, and computed_value
-- becomes NULL -- a real caller asking for a short intraday window silently gets
-- "no data" instead of the real 0% the function's own comment promises. Live-reproduced
-- (before this fix) at exactly 3 hours of every 24 by
-- scripts/db-tests/procurement-vendor-performance.sql's own now()-relative window.
--
-- Fix: replace "the day 24 hours before the exclusive end" with "the calendar date of
-- the LAST INSTANT actually inside the exclusive-end window" -- i.e. window_end minus
-- one microsecond (timestamptz's own finest resolution), not minus one day. This is
-- exactly the same value for every whole-day-aligned window the old formula already
-- handled correctly (Jan3 00:00 - 1 microsecond is Jan2 23:59:59.999999, same date as
-- Jan3 00:00 - 1 day), and correctly yields the window's own start date -- never an
-- earlier one -- for every sub-24-hour or otherwise-unaligned window, since window_end
-- minus an epsilon can never fall on a date before window_start's own date once
-- window_end > window_start (already implied by every real caller of this function).
--
-- No already-applied migration is edited -- this is a genuine CREATE OR REPLACE of an
-- existing function, no signature change, so its own grants (already app.*-internal,
-- no direct EXECUTE grant of its own -- called only from app.calculate_vendor_kpi_metrics)
-- carry forward automatically.

create or replace function app._calc_vendor_kpi_rate_validity(p_tenant_id uuid, p_vendor_master_id uuid, p_window_start timestamptz, p_window_end timestamptz)
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
  select array_agg(id) into v_ids
  from app.vendor_rate_versions vr
  where vr.tenant_id = p_tenant_id and vr.vendor_master_id = p_vendor_master_id and vr.approval_status = 'approved'
    and vr.effective_from < p_window_end and (vr.effective_to is null or vr.effective_to > p_window_start)
    and not exists (select 1 from app.vendor_kpi_source_disputes d where d.kpi_code = 'rate_validity' and d.source_id = vr.id and d.status = 'upheld');

  -- RGL-BLK-004 fix: the upper bound is the calendar date of the last instant actually
  -- inside the exclusive-end window (window_end - 1 microsecond), not window_end minus a
  -- flat 24 hours -- see this migration's own header comment for why the flat-24-hour
  -- version collapses to an empty series for any sub-24-hour or otherwise day-unaligned
  -- window.
  with days as (
    select generate_series(p_window_start::date, (p_window_end - interval '1 microsecond')::date, interval '1 day') as d
  )
  select
    count(*) filter (
      where exists (
        select 1 from app.vendor_rate_versions vr
        where vr.id = any (coalesce(v_ids, '{}'::uuid[]))
          and vr.effective_from <= days.d::timestamptz and (vr.effective_to is null or vr.effective_to > days.d::timestamptz)
      )
    ),
    count(*)
  into v_num, v_den
  from days;

  r.raw_numerator := v_num;
  r.raw_denominator := v_den;
  r.sample_size := coalesce(v_den, 0);
  r.is_computable := coalesce(v_den, 0) > 0;
  r.computed_value := case when v_den > 0 then round(100.0 * v_num / v_den, 2) else null end;
  r.computation_note := case when v_num = 0 then 'no_valid_rate_coverage: this vendor has no approved rate version covering any day of the window' else null end;
  r.source_evidence := jsonb_build_object('window_days', coalesce(v_den, 0), 'covered_days', coalesce(v_num, 0), 'contributing_source_ids', to_jsonb((coalesce(v_ids, '{}'::uuid[]))[1:50]));
  return r;
end;
$$;

comment on function app._calc_vendor_kpi_rate_validity is
  'PRC-264, RGL-BLK-004 hardened: % of calendar days in the window covered by at least one approved app.vendor_rate_versions row (effective_from/effective_to). is_computable is true whenever the window itself is non-empty (window_days is always > 0, genuinely true now for every window shape, not only whole-day-aligned ones) -- a vendor with zero coverage genuinely scores 0%, a real, meaningful result, not a missing-data case (distinct from every other calculator, where a zero-denominator means "nothing to measure"). The days-in-window upper bound is window_end minus one microsecond, not minus one day -- see this migration''s own header comment for the sub-24-hour collapse this replaces.';
