import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseRoutePlanningScenario,
  parseRoutePlanningStop,
  parseRoutePlanningCandidatePlan,
  parseCanonicalPositionForPlanning,
  AddRoutePlanningStopInputSchema,
  AddRoutePlanningConstraintInputSchema,
} from "./route-load-planning.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const SCENARIO_ID = "423e4567-e89b-12d3-a456-426614174000";
const CANDIDATE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseRoutePlanningScenario", () => {
  test("maps a draft scenario with no canonical-position snapshot yet", () => {
    const scenario = parseRoutePlanningScenario({
      id: SCENARIO_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      idempotency_key: "idem-scenario-1",
      status: "draft",
      requested_weight_kg: 800,
      requested_volume_cbm: 10,
      job_id: null,
      canonical_position_snapshot: null,
      canonical_position_captured_at: null,
      owner_user_id: ACTOR_ID,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(scenario.status, "draft");
    assert.equal(scenario.requestedWeightKg, 800);
    assert.equal(scenario.canonicalPositionSnapshot, null);
  });

  test("maps a validated scenario carrying an honest not_tracked snapshot", () => {
    const scenario = parseRoutePlanningScenario({
      id: SCENARIO_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      idempotency_key: "idem-scenario-2",
      status: "validated",
      requested_weight_kg: null,
      requested_volume_cbm: null,
      job_id: null,
      canonical_position_snapshot: { tracking_status: "not_tracked", is_usable: false },
      canonical_position_captured_at: "2026-08-01T00:00:00.000Z",
      owner_user_id: null,
      record_version: 1,
      created_by: null,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.deepEqual(scenario.canonicalPositionSnapshot, { tracking_status: "not_tracked", is_usable: false });
  });
});

describe("parseRoutePlanningStop", () => {
  test("extracts longitude/latitude from a GeoJSON Point", () => {
    const stop = parseRoutePlanningStop({
      id: SCENARIO_ID,
      tenant_id: TENANT_ID,
      scenario_id: SCENARIO_ID,
      stop_sequence: 1,
      stop_type: "pickup",
      location_name: "Jakarta Warehouse",
      address: null,
      location_geojson: { type: "Point", coordinates: [106.8456, -6.2088] },
      time_window_start: null,
      time_window_end: null,
      created_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(stop.longitude, 106.8456);
    assert.equal(stop.latitude, -6.2088);
  });

  test("nulls longitude/latitude when no geography was recorded", () => {
    const stop = parseRoutePlanningStop({
      id: SCENARIO_ID,
      tenant_id: TENANT_ID,
      scenario_id: SCENARIO_ID,
      stop_sequence: 2,
      stop_type: "delivery",
      location_name: "Bandung Warehouse",
      address: null,
      location_geojson: null,
      time_window_start: null,
      time_window_end: null,
      created_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(stop.longitude, null);
    assert.equal(stop.latitude, null);
  });
});

describe("parseRoutePlanningCandidatePlan", () => {
  test("maps a feasible candidate", () => {
    const candidate = parseRoutePlanningCandidatePlan({
      id: CANDIDATE_ID,
      tenant_id: TENANT_ID,
      scenario_id: SCENARIO_ID,
      plan_rank: 1,
      algorithm_version: "baseline-v1",
      feasible: true,
      infeasibility_reasons: null,
      vehicle_master_id: ACTOR_ID,
      driver_master_id: ACTOR_ID,
      total_distance_km: 117.3,
      estimated_duration_minutes: 176,
      capacity_utilization_pct: 80,
      generated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(candidate.feasible, true);
    assert.equal(candidate.planRank, 1);
  });

  test("maps an infeasible placeholder candidate carrying its own reasons", () => {
    const candidate = parseRoutePlanningCandidatePlan({
      id: CANDIDATE_ID,
      tenant_id: TENANT_ID,
      scenario_id: SCENARIO_ID,
      plan_rank: 1,
      algorithm_version: "baseline-v1",
      feasible: false,
      infeasibility_reasons: ["no_eligible_vehicle"],
      vehicle_master_id: null,
      driver_master_id: null,
      total_distance_km: null,
      estimated_duration_minutes: null,
      capacity_utilization_pct: null,
      generated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(candidate.feasible, false);
    assert.deepEqual(candidate.infeasibilityReasons, ["no_eligible_vehicle"]);
  });
});

describe("parseCanonicalPositionForPlanning", () => {
  test("maps the honest not_tracked/unusable projection (no ATW-226F writer exists yet)", () => {
    const position = parseCanonicalPositionForPlanning({
      tracking_status: "not_tracked",
      freshness_status: null,
      accuracy_meters: null,
      last_position_at: null,
      authoritative_source_type: null,
      tracking_entitled: false,
      is_usable: false,
    });
    assert.equal(position.trackingStatus, "not_tracked");
    assert.equal(position.isUsable, false);
  });
});

describe("AddRoutePlanningStopInputSchema", () => {
  test("rejects an out-of-range latitude", () => {
    assert.throws(() =>
      AddRoutePlanningStopInputSchema.parse({
        scenarioId: SCENARIO_ID,
        stopSequence: 1,
        stopType: "pickup",
        locationName: "Jakarta Warehouse",
        address: null,
        longitude: 106.8456,
        latitude: 91,
        timeWindowStart: null,
        timeWindowEnd: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts null coordinates", () => {
    const parsed = AddRoutePlanningStopInputSchema.parse({
      scenarioId: SCENARIO_ID,
      stopSequence: 1,
      stopType: "transfer",
      locationName: "Surabaya Transfer Yard",
      address: null,
      longitude: null,
      latitude: null,
      timeWindowStart: null,
      timeWindowEnd: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.longitude, null);
  });
});

describe("AddRoutePlanningConstraintInputSchema", () => {
  test("rejects an unknown constraint key", () => {
    assert.throws(() =>
      AddRoutePlanningConstraintInputSchema.parse({
        scenarioId: SCENARIO_ID,
        constraintType: "hard",
        constraintKey: "max_speed_kmh",
        constraintValue: { value: 100 },
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts a valid max_weight_kg constraint", () => {
    const parsed = AddRoutePlanningConstraintInputSchema.parse({
      scenarioId: SCENARIO_ID,
      constraintType: "hard",
      constraintKey: "max_weight_kg",
      constraintValue: { value: 900 },
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.constraintKey, "max_weight_kg");
  });
});
