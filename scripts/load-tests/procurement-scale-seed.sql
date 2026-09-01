-- ISS-2026-063 sub-item (2) closure -- Procurement dashboard/list large-scale
-- EXPLAIN load proof, extended to the 5 named surfaces PRC-268/PRC-269 did not
-- cover (scorecards, match-case list, capacity, assignment, export/report-run
-- history). Mirrors PRC-268's own reproduction shape exactly (see
-- docs/build-log/phase-06/PRC-268.md section 5 / PRC-269.md section 2 Fix 6):
-- a synthetic multi-tenant scale with one tenant deliberately holding ~68% of
-- each target table (the same adversarial skew ratio PRC-269 measured its own
-- fix against), built in a throwaway database, never wired into `pnpm run
-- db:test` (a multi-thousand-row seed does not belong in the standing
-- regression gate -- PRC-269's own precedent).
--
-- Run once, by scripts/load-tests/procurement-scale-explain.sh, against a
-- fresh disposable database that already has every supabase/migrations/*.sql
-- applied (via the same shared scripts/db-tests/lib/setup-disposable-db.sh
-- this repository's other load-test/db-test harnesses already use -- never
-- duplicated).
--
-- Design note (disclosed, mirrors scripts/load-tests/seed.sql section 1's own
-- established discipline): the SHALLOW per-tenant setup (tenants, one shared
-- loadtest actor, vendors) is bulk INSERT...SELECT directly into the
-- already-migrated tables -- these are cheap, one-time, non-measured
-- precondition rows, never the thing any scenario measures. The DEEP
-- commercial-pipeline chain a real vendor-bill match case sits behind (lead ->
-- prospect -> opportunity -> quotation -> job-order-handoff -> job order ->
-- shipment order -> actual cost -> finance vendor bill) is built ONCE per
-- tenant (26 total, not 7,500) via the same direct-insert technique, then
-- REUSED across every match-case/assignment-invitation row that tenant owns --
-- exactly the same "bulk-seed only the PRECONDITION rows, never the thing
-- being measured" principle scripts/load-tests/seed.sql's own header already
-- establishes for its own wms_pick_tasks/wms_putaway_tasks preconditions. No
-- FK is ever synthesized (every id referenced by a NOT NULL foreign key is a
-- real row in the real parent table, seeded here); only the volume/cardinality
-- is compressed relative to what 5,000 fully-independent real business
-- pipelines would look like -- irrelevant to what this file measures (planner
-- behavior against row COUNT and skew at the leaf table the target RPC's own
-- query shape actually scans, never the depth of the pipeline above it).
--
-- Seeded volume (real counts, printed by this file's own row-count summary):
--   26 tenants (tenant #1 = the deliberately skewed "big" tenant; #2-26 share
--   the remainder evenly), 1 shared loadtest actor (auth.users), 20 vendors
--   per tenant (520 total, app.master_records + app.vendor_profiles), one
--   commercial-pipeline chain per tenant (26 leads/prospects/opportunities/
--   quotations/handoffs/job_orders) feeding 5 shipment_orders per tenter
--   (130 total, reused many-to-one by the actual-cost/bill rows below).
--   Five independently-skewed target tables, ~7,500 rows each, tenant #1
--   holding ~68% of each (matching PRC-269's own 68.0% reproduction ratio
--   exactly): app.vendor_kpi_scorecards, app.vendor_bill_match_cases (+ one
--   real app.finance_vendor_bills + app.shipment_actual_costs row per match
--   case, its own real NOT NULL FK target), app.vendor_capacity_offers,
--   app.vendor_assignment_invitations, app.report_runs (spread across the
--   ten real procurement report_type_code rows PRC-266's own migration
--   already registered -- never a fabricated code).

\set ON_ERROR_STOP on

\echo '>> procurement-scale-seed: 26 tenants (tenant #1 = skewed), 1 shared loadtest actor'
create temporary table load_tenant (tenant_seq int primary key, tenant_id uuid not null, target_rows int not null);

do $$
declare
  v_actor_id uuid := '00000000-0000-0000-0000-0000000c0601';
begin
  insert into auth.users (id, email) values (v_actor_id, 'prc063loadtest@loadtest.test')
  on conflict (id) do nothing;

  insert into app.tenants (slug, name, canonical_status, idempotency_key, created_by)
  select 'prc063-t' || g, 'PRC-063 Load Tenant ' || g, 'active', 'idem-prc063-tenant-' || g, 'prc063loadtest'
  from generate_series(1, 26) g;

  -- Tenant #1 gets ~68% of every target table's rows (5,100 of 7,500,
  -- PRC-269's own exact ratio); tenants #2-26 (25 tenants) split the
  -- remaining 32% evenly (96 each, 2,400 total) -- 7,500 grand total per
  -- target table, matching PRC-269's own 7,497-row reproduction scale.
  insert into load_tenant (tenant_seq, tenant_id, target_rows)
  select g, t.id, case when g = 1 then 5100 else 96 end
  from generate_series(1, 26) g
  join app.tenants t on t.slug = 'prc063-t' || g;
end $$;

\echo '>> procurement-scale-seed: 520 vendors (20 per tenant), app.master_records + app.vendor_profiles, bulk INSERT...SELECT (bypasses the real per-vendor RPC chain -- volume/precondition rows only, never what any scenario below measures)'
create temporary table load_vendor (tenant_seq int not null, vendor_seq int not null, vendor_master_id uuid not null, primary key (tenant_seq, vendor_seq));

do $$
begin
  insert into app.master_records (id, master_type_code, tenant_id, code, name, canonical_status, created_by)
  select gen_random_uuid(), 'vendor', lt.tenant_id, 'PRC063-VEND-' || lt.tenant_seq || '-' || v, 'PRC-063 Load Vendor ' || lt.tenant_seq || '-' || v, 'active', 'prc063loadtest'
  from load_tenant lt cross join generate_series(1, 20) v;

  insert into app.vendor_profiles (master_record_id, tenant_id, legal_name, intake_source, lifecycle_status, created_by)
  select mr.id, mr.tenant_id, mr.name, 'staff_created', 'active', 'prc063loadtest'
  from app.master_records mr
  where mr.master_type_code = 'vendor' and mr.code like 'PRC063-VEND-%';

  insert into load_vendor (tenant_seq, vendor_seq, vendor_master_id)
  select lt.tenant_seq, v, mr.id
  from load_tenant lt
  cross join generate_series(1, 20) v
  join app.master_records mr on mr.tenant_id = lt.tenant_id and mr.code = 'PRC063-VEND-' || lt.tenant_seq || '-' || v;
end $$;

\echo '>> procurement-scale-seed: one real commercial-pipeline chain per tenant (lead -> prospect -> opportunity -> quotation -> job-order-handoff -> job_order), direct INSERT (every column a real value of the shape the real RPC chain would produce -- see this file''s own header design note); feeds the shipment_orders pool below, never itself the thing measured'
create temporary table load_job_order (tenant_seq int primary key, job_order_id uuid not null, account_id uuid not null);
create temporary table load_quote (tenant_seq int primary key, quotation_id uuid not null);

do $$
declare
  v_actor_id uuid := '00000000-0000-0000-0000-0000000c0601';
begin
  -- status='qualified' first (converted_prospect_id must stay null until a real
  -- prospect row exists to point at -- leads_converted_prospect_check), then
  -- flipped to 'converted' once the prospect below is real.
  insert into app.leads (id, tenant_id, source, contact_name, email, duplicate_fingerprint, status, created_by)
  select gen_random_uuid(), lt.tenant_id, 'manual', 'PRC-063 Load Contact ' || lt.tenant_seq, 'prc063-load-' || lt.tenant_seq || '@loadtest.test', 'prc063-load-fp-' || lt.tenant_seq, 'qualified', 'prc063loadtest'
  from load_tenant lt;

  insert into app.prospects (id, tenant_id, lead_id, legal_name, duplicate_fingerprint, contact_name, status, created_by)
  select gen_random_uuid(), l.tenant_id, l.id, 'PRC-063 Load Prospect ' || t.tenant_seq, 'prc063-load-prospect-fp-' || t.tenant_seq, 'PRC-063 Load Contact', 'active', 'prc063loadtest'
  from app.leads l
  join load_tenant t on t.tenant_id = l.tenant_id
  where l.email = 'prc063-load-' || t.tenant_seq || '@loadtest.test';

  update app.leads l set status = 'converted', converted_at = now(), converted_prospect_id = p.id
  from app.prospects p
  where p.lead_id = l.id and l.email like 'prc063-load-%@loadtest.test';

  insert into app.opportunities (id, tenant_id, prospect_id, name, stage, created_by)
  select gen_random_uuid(), p.tenant_id, p.id, 'PRC-063 Load Opportunity', 'ready_for_costing', 'prc063loadtest'
  from app.prospects p
  where p.legal_name = 'PRC-063 Load Prospect ' || (select t.tenant_seq from load_tenant t where t.tenant_id = p.tenant_id);

  insert into app.accounts (id, tenant_id, legal_name, duplicate_fingerprint, customer_status, status, created_by)
  select gen_random_uuid(), lt.tenant_id, 'PRC-063 Load Account ' || lt.tenant_seq, 'prc063-load-account-fp-' || lt.tenant_seq, 'active', 'active', 'prc063loadtest'
  from load_tenant lt;

  -- root_quotation_id self-references the row's own id (COM-152's own "first
  -- version is its own root" convention) -- generated once per tenant into a
  -- temp table first, rather than calling gen_random_uuid() twice in the same
  -- SELECT (a non-correlated LATERAL subquery here was live-reproduced to be
  -- evaluated ONCE for the whole statement, not once per row, giving every
  -- row the identical id -- a real planner-flattening trap, not a typo).
  insert into load_quote (tenant_seq, quotation_id)
  select tenant_seq, gen_random_uuid() from load_tenant;

  insert into app.quotations (id, tenant_id, quote_number, opportunity_id, source_opportunity_version, prospect_id, currency, validity_to, root_quotation_id, version_number, is_current, status, created_by)
  select lq.quotation_id, o.tenant_id, 'PRC063-QUOTE-' || t.tenant_seq, o.id, o.record_version, o.prospect_id, 'IDR', now() + interval '30 days', lq.quotation_id, 1, true, 'submitted', 'prc063loadtest'
  from app.opportunities o
  join load_tenant t on t.tenant_id = o.tenant_id
  join load_quote lq on lq.tenant_seq = t.tenant_seq
  where o.name = 'PRC-063 Load Opportunity';

  insert into app.job_order_handoffs (id, tenant_id, quotation_id, account_id, status, payload, payload_hash, prepared_by_auth_user_id, created_by)
  select gen_random_uuid(), q.tenant_id, q.id, a.id, 'prepared', '{}'::jsonb, md5(q.id::text), v_actor_id, 'prc063loadtest'
  from app.quotations q
  join load_tenant t on t.tenant_id = q.tenant_id
  join app.accounts a on a.tenant_id = q.tenant_id and a.legal_name = 'PRC-063 Load Account ' || t.tenant_seq
  where q.quote_number = 'PRC063-QUOTE-' || t.tenant_seq;

  insert into app.job_orders (id, tenant_id, job_number, source_handoff_id, quotation_id, account_id, customer_snapshot, cargo_service_snapshot, revenue_snapshot, acceptance_snapshot, status, created_by)
  select gen_random_uuid(), h.tenant_id, 'PRC063-JO-' || t.tenant_seq, h.id, h.quotation_id, h.account_id, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'confirmed', 'prc063loadtest'
  from app.job_order_handoffs h
  join load_tenant t on t.tenant_id = h.tenant_id
  where h.payload_hash = md5(h.quotation_id::text);

  insert into load_job_order (tenant_seq, job_order_id, account_id)
  select t.tenant_seq, jo.id, jo.account_id
  from app.job_orders jo
  join load_tenant t on t.tenant_id = jo.tenant_id
  where jo.job_number = 'PRC063-JO-' || t.tenant_seq;
end $$;

\echo '>> procurement-scale-seed: 130 shipment_orders (5 per tenant, reused many-to-one below), direct INSERT'
create temporary table load_shipment (tenant_seq int not null, shipment_seq int not null, shipment_order_id uuid not null, primary key (tenant_seq, shipment_seq));

do $$
begin
  insert into app.shipment_orders (id, tenant_id, job_order_id, shipment_number, idempotency_key, status, shipper_account_id, consignee_snapshot, cargo_service_snapshot, service_type, mode, origin, destination, created_by)
  select gen_random_uuid(), t.tenant_id, jo.job_order_id, 'PRC063-SHP-' || jo.tenant_seq || '-' || s, 'idem-prc063-shp-' || jo.tenant_seq || '-' || s, 'confirmed', jo.account_id, '{}'::jsonb, '{}'::jsonb, 'ocean_freight', 'sea', 'Jakarta', 'Surabaya', 'prc063loadtest'
  from load_job_order jo
  join load_tenant t on t.tenant_seq = jo.tenant_seq
  cross join generate_series(1, 5) s;

  insert into load_shipment (tenant_seq, shipment_seq, shipment_order_id)
  select t.tenant_seq, s, so.id
  from load_tenant t
  cross join generate_series(1, 5) s
  join app.shipment_orders so on so.tenant_id = t.tenant_id and so.shipment_number = 'PRC063-SHP-' || t.tenant_seq || '-' || s;
end $$;

\echo '>> procurement-scale-seed: target-table 1/5 -- app.vendor_kpi_scorecards, ~7,500 rows, tenant #1 68%'
-- window_start/end is derived from n itself (not n % 12) so every row's own
-- window is globally distinct within a tenant regardless of which vendor it
-- lands on -- vendor_kpi_scorecards_current_unique is (tenant_id,
-- vendor_master_id, window_start, window_end); using n % 12 collided across
-- the ~20-vendor round-robin at this row count (live-reproduced), n does not.
insert into app.vendor_kpi_scorecards (tenant_id, vendor_master_id, window_start, window_end, is_current, status, composite_score, band, computable_weight_total, total_weight_defined, created_by)
select lt.tenant_id, lv.vendor_master_id,
  now() - (n || ' hours')::interval - interval '1 month',
  now() - (n || ' hours')::interval,
  (n <= 20), 'published', 50 + (n % 50), (array['excellent','good','watch','poor'])[1 + (n % 4)], 100, 100, 'prc063loadtest'
from load_tenant lt
join lateral generate_series(1, lt.target_rows) n on true
join lateral (select vendor_master_id from load_vendor v where v.tenant_seq = lt.tenant_seq order by ((n + v.vendor_seq) % 20) limit 1) lv on true;

\echo '>> procurement-scale-seed: target-table 2/5 -- app.finance_vendor_bills + app.shipment_actual_costs (real NOT NULL precondition, one pair per match case) then app.vendor_bill_match_cases, ~7,500 rows, tenant #1 68%'
create temporary table load_actual_cost (tenant_id uuid not null, seq int not null, actual_cost_id uuid not null);
create temporary table load_bill (tenant_id uuid not null, seq int not null, bill_id uuid not null, vendor_master_id uuid not null);

do $$
begin
  -- is_current=false for every row: app.shipment_actual_costs only allows ONE
  -- is_current=true row per shipment_order_id (shipment_actual_costs_one_
  -- current_idx), and the shipment_orders pool above is deliberately reused
  -- many-to-one -- these rows exist only as a real, valid NOT NULL FK target
  -- for finance_vendor_bills.actual_cost_id below, never themselves read by
  -- any of the 5 target-table query shapes this file measures.
  insert into app.shipment_actual_costs (id, tenant_id, shipment_order_id, is_current, status, currency, total_amount, created_by)
  select gen_random_uuid(), lt.tenant_id, ls.shipment_order_id, false, 'approved', 'IDR', 10000000 + (n * 1000), 'prc063loadtest'
  from load_tenant lt
  join lateral generate_series(1, lt.target_rows) n on true
  join lateral (select shipment_order_id from load_shipment s where s.tenant_seq = lt.tenant_seq order by ((n) % 5) limit 1) ls on true;

  insert into load_actual_cost (tenant_id, seq, actual_cost_id)
  select tenant_id, row_number() over (partition by tenant_id order by created_at), id
  from app.shipment_actual_costs
  where created_by = 'prc063loadtest';

  insert into app.finance_vendor_bills (id, tenant_id, vendor_master_id, actual_cost_id, currency, status, subtotal_amount, bill_date, due_date, created_by)
  select gen_random_uuid(), ac.tenant_id, lv.vendor_master_id, ac.actual_cost_id, 'IDR', 'posted', 10000000, current_date, current_date + 30, 'prc063loadtest'
  from load_actual_cost ac
  join load_tenant lt on lt.tenant_id = ac.tenant_id
  join lateral (select vendor_master_id from load_vendor v where v.tenant_seq = lt.tenant_seq order by ((ac.seq + v.vendor_seq) % 20) limit 1) lv on true;

  insert into load_bill (tenant_id, seq, bill_id, vendor_master_id)
  select b.tenant_id, ac.seq, b.id, b.vendor_master_id
  from app.finance_vendor_bills b
  join load_actual_cost ac on ac.actual_cost_id = b.actual_cost_id
  where b.created_by = 'prc063loadtest';

  insert into app.vendor_bill_match_cases (tenant_id, bill_id, vendor_master_id, currency, match_mode, is_current, total_vendor_stated_amount, total_evidence_amount, overall_status, readiness_status, duplicate_fingerprint, idempotency_key, created_by)
  select tenant_id, bill_id, vendor_master_id, 'IDR', 'non_po', true, 10000000, 10000000,
    (array['pending','matched','exception'])[1 + (seq % 3)], (array['not_ready','ready_for_finance'])[1 + (seq % 2)],
    'prc063-load-fp-' || tenant_id || '-' || seq, 'idem-prc063-matchcase-' || tenant_id || '-' || seq, 'prc063loadtest'
  from load_bill;
end $$;

\echo '>> procurement-scale-seed: target-table 3/5 -- app.vendor_capacity_offers, ~7,500 rows, tenant #1 68%'
insert into app.vendor_capacity_offers (tenant_id, vendor_master_id, service_type, resource_type, quantity, uom, window_start, window_end, status, created_by)
select lt.tenant_id, lv.vendor_master_id, 'ocean_freight', 'general', 100, 'CBM',
  now() + ((n % 30) || ' days')::interval, now() + ((n % 30) + 5 || ' days')::interval,
  (array['draft','published','archived'])[1 + (n % 3)], 'prc063loadtest'
from load_tenant lt
join lateral generate_series(1, lt.target_rows) n on true
join lateral (select vendor_master_id from load_vendor v where v.tenant_seq = lt.tenant_seq order by ((n + v.vendor_seq) % 20) limit 1) lv on true;

\echo '>> procurement-scale-seed: target-table 4/5 -- app.vendor_assignment_invitations, ~7,500 rows, tenant #1 68% (reuses the same 130-shipment_order pool -- no uniqueness constraint on shipment_order_id alone, so many invitations legitimately reference the same shipment across real-world resourcing rounds too)'
-- status='expired' for every row: 'declined'/'cancelled' both require a
-- non-empty reason column (irrelevant to the query shape this file measures),
-- and 'invited'/'accepted' are capped at ONE live row per (tenant_id,
-- shipment_order_id) by vendor_assignment_invitations_one_live_per_shipment_
-- unique -- which the reused 5-shipment_order-per-tenant pool would violate
-- immediately at this row count. 'expired' is a real, unconstrained terminal
-- status and is what most real invitations settle into over time anyway.
insert into app.vendor_assignment_invitations (tenant_id, shipment_order_id, vendor_master_id, status, created_by)
select lt.tenant_id, ls.shipment_order_id, lv.vendor_master_id, 'expired', 'prc063loadtest'
from load_tenant lt
join lateral generate_series(1, lt.target_rows) n on true
join lateral (select shipment_order_id from load_shipment s where s.tenant_seq = lt.tenant_seq order by (n % 5) limit 1) ls on true
join lateral (select vendor_master_id from load_vendor v where v.tenant_seq = lt.tenant_seq order by ((n + v.vendor_seq) % 20) limit 1) lv on true;

\echo '>> procurement-scale-seed: target-table 5/5 -- app.report_runs, ~7,500 rows, tenant #1 68%, spread across the 10 real procurement report_type_code rows PRC-266''s own migration registered'
do $$
declare
  v_actor_id uuid := '00000000-0000-0000-0000-0000000c0601';
  -- the 10 REAL app.report_types rows PRC-266's own migration registered as
  -- exportable (not the 11 app.procurement_metric_definitions codes -- the
  -- compliance-expiry queue is deliberately not one of them, see that
  -- migration's own header: "a live work-queue, not a bounded export target").
  v_codes text[] := array(
    select rt.code from app.report_types rt
    join app.procurement_metric_definitions pmd on pmd.source_function = rt.source_function and pmd.is_current
    order by rt.code
  );
begin
  insert into app.report_runs (tenant_id, report_type_code, run_type, status, requested_by_auth_user_id, requested_at, completed_at, created_by)
  select lt.tenant_id, v_codes[1 + (n % array_length(v_codes, 1))], 'export', 'completed', v_actor_id,
    now() - (n || ' minutes')::interval, now() - (n || ' minutes')::interval + interval '5 seconds', 'prc063loadtest'
  from load_tenant lt
  join lateral generate_series(1, lt.target_rows) n on true;
end $$;

\echo '>> procurement-scale-seed: row-count summary (real counts, not a toy fixture)'
select 'tenants' as entity, count(*) from app.tenants where slug like 'prc063-t%'
union all select 'vendors', count(*) from app.master_records where code like 'PRC063-VEND-%'
union all select 'shipment_orders (pool)', count(*) from app.shipment_orders where shipment_number like 'PRC063-SHP-%'
union all select 'vendor_kpi_scorecards', count(*) from app.vendor_kpi_scorecards where created_by = 'prc063loadtest'
union all select 'finance_vendor_bills', count(*) from app.finance_vendor_bills where created_by = 'prc063loadtest'
union all select 'vendor_bill_match_cases', count(*) from app.vendor_bill_match_cases where created_by = 'prc063loadtest'
union all select 'vendor_capacity_offers', count(*) from app.vendor_capacity_offers where created_by = 'prc063loadtest'
union all select 'vendor_assignment_invitations', count(*) from app.vendor_assignment_invitations where created_by = 'prc063loadtest'
union all select 'report_runs', count(*) from app.report_runs where created_by = 'prc063loadtest';

select 'tenant #1 (skewed) share' as check_label,
  (select count(*) from app.vendor_kpi_scorecards k join app.tenants t on t.id = k.tenant_id where t.slug = 'prc063-t1') as scorecards_t1,
  (select count(*) from app.vendor_bill_match_cases m join app.tenants t on t.id = m.tenant_id where t.slug = 'prc063-t1') as match_cases_t1,
  (select count(*) from app.vendor_capacity_offers c join app.tenants t on t.id = c.tenant_id where t.slug = 'prc063-t1') as capacity_t1,
  (select count(*) from app.vendor_assignment_invitations a join app.tenants t on t.id = a.tenant_id where t.slug = 'prc063-t1') as assignment_t1,
  (select count(*) from app.report_runs r join app.tenants t on t.id = r.tenant_id where t.slug = 'prc063-t1') as report_runs_t1;
