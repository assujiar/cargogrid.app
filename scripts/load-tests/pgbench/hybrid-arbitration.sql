-- Scenario 8 (CG-S10-ATW-024, Prompt 243, fix-pass addition -- adversarial review):
-- concurrent, conflicting multi-source telemetry arbitration against a SHARED,
-- deliberately small set of hot vehicles (VEH-LOAD-0001..VEH-LOAD-0020) -- the real
-- "Hybrid: duplicate/conflicting coordinates, arbitration throughput, source switch and
-- hysteresis" target profile Prompt 243 section 17 names, which the original checkpoint
-- left entirely unexercised under real concurrent database load (the correctness
-- reviewer's own Finding 1: a live-reproduced HIGH-severity read-decide-then-blind-write
-- TOCTOU race in app.arbitrate_and_project_vehicle_position -- see
-- 20260730320000_create_advanced_tms_shipment_tracking_health_writer.sql's own comment
-- at the per-vehicle pg_advisory_xact_lock added there for the fix). Each transaction
-- calls the REAL, unmodified (now-fixed) app.arbitrate_and_project_vehicle_position
-- directly for one randomly-chosen hot vehicle, a randomly-chosen source_type, and an
-- event_at drawn from a tight, overlapping recent window -- deliberately maximizing
-- genuine ordering ambiguity/ contention across concurrent sessions, not merely load
-- volume. scripts/load-tests/run.sh's own post-run SQL checks whether
-- vehicle_current_positions ever moved backward relative to the real applied event
-- history -- the exact invariant Finding 1 found violated.
--
-- __TENANT_ID__ is a sed-rendered placeholder -- see inventory-movement.sql's own
-- header for why (pgbench's own quoted-variable substitution is not used in this
-- environment).
select app.arbitrate_and_project_vehicle_position(
  '__TENANT_ID__'::uuid,
  (select mr.id from app.master_records mr where mr.tenant_id = '__TENANT_ID__'::uuid and mr.master_type_code = 'vehicle' and mr.code between 'VEH-LOAD-0001' and 'VEH-LOAD-0020' order by random() limit 1),
  (array['driver_mobile', 'direct_device', 'third_party_platform'])[1 + floor(random() * 3)::int],
  gen_random_uuid(),
  now() - (random() * interval '2 seconds'),
  now(),
  app.geojson_point_to_geography(jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(106.8461 + (random() - 0.5) * 0.01, -6.2089 + (random() - 0.5) * 0.01))),
  (30 + random() * 60)::numeric,
  (random() * 360)::numeric,
  (3 + random() * 10)::numeric
);
