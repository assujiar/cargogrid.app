-- CG-S10-ATW-027 (Prompt 246) -- closes ISS-2026-022.
--
-- app.route_planning_position_staleness_tolerance_seconds's own comment (added at
-- ATW-224, 20260729320000_create_advanced_tms_route_load_planning.sql) said this
-- tolerance was "currently unreachable in practice: app.shipment_tracking_health has
-- no live writer yet (ATW-226F)". That became false at ATW-024 (Prompt 243), which
-- wired a real writer (app.recalculate_shipment_tracking_health /
-- app.reconcile_shipment_tracking_health, closing ISS-2026-009's own core claim) into
-- app.arbitrate_and_project_vehicle_position. ATW-026 (Prompt 245)'s own transport
-- golden-path E2E composition is the first real, executed proof the code path is now
-- reachable: app.get_canonical_position_for_planning.is_usable became true against a
-- live-tracked shipment.
--
-- COMMENT ON FUNCTION carries no privilege (no REVOKE/GRANT needed, matching the
-- PLT-138 precedent for a documentation-accuracy-only repair) and does not rebuild the
-- function body -- the function's own behavior is completely unchanged by this
-- migration; only its comment is corrected. The already-applied ATW-224 migration file
-- itself is untouched.
comment on function app.route_planning_position_staleness_tolerance_seconds is
  'ATW-224: the governed freshness tolerance (seconds) app.get_canonical_position_for_planning applies -- a disclosed reasoned default matching the same class as app.route_planning_default_speed_kmh(). Reachable since ATW-024 (Prompt 243, ISS-2026-009): app.shipment_tracking_health gained a real writer (app.recalculate_shipment_tracking_health / app.reconcile_shipment_tracking_health), so a live-tracked shipment''s freshness now genuinely depends on this tolerance rather than always reporting not_tracked/unknown. First live-executed proof: ATW-026''s (Prompt 245) transport golden-path E2E composition. Corrected at ATW-027 (Prompt 246), closing ISS-2026-022.';
