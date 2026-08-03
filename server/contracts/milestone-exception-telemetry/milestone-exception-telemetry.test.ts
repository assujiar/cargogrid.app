import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseShipmentLegEtaProjection, RebaselineShipmentLegScheduleInputSchema } from "./milestone-exception-telemetry.ts";

const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseShipmentLegEtaProjection", () => {
  test("maps a computable projection", () => {
    const projection = parseShipmentLegEtaProjection({
      shipment_leg_id: LEG_ID,
      computable: true,
      reason: null,
      position_status: "healthy",
      remaining_distance_km: "42.5",
      estimated_arrival_at: "2026-08-03T12:00:00.000Z",
      planned_arrival_at: "2026-08-03T10:00:00.000Z",
      delay_minutes: "120",
      downstream_leg_count: 2,
    });
    assert.equal(projection.computable, true);
    assert.equal(projection.remainingDistanceKm, 42.5);
    assert.equal(projection.delayMinutes, 120);
    assert.equal(projection.downstreamLegCount, 2);
  });

  test("maps an honestly uncomputable projection with a named reason, never a fabricated estimate", () => {
    const projection = parseShipmentLegEtaProjection({
      shipment_leg_id: LEG_ID,
      computable: false,
      reason: "no_live_position",
      position_status: null,
      remaining_distance_km: null,
      estimated_arrival_at: null,
      planned_arrival_at: "2026-08-03T10:00:00.000Z",
      delay_minutes: null,
      downstream_leg_count: 0,
    });
    assert.equal(projection.computable, false);
    assert.equal(projection.reason, "no_live_position");
    assert.equal(projection.estimatedArrivalAt, null);
  });
});

describe("RebaselineShipmentLegScheduleInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = RebaselineShipmentLegScheduleInputSchema.parse({
      shipmentLegId: LEG_ID,
      newPlannedDepartureAt: "2026-08-04T00:00:00.000Z",
      newPlannedArrivalAt: "2026-08-05T00:00:00.000Z",
      reason: "customer requested a later pickup window",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "dispatcher",
    });
    assert.equal(parsed.reason, "customer requested a later pickup window");
  });

  test("rejects an empty reason", () => {
    assert.throws(() =>
      RebaselineShipmentLegScheduleInputSchema.parse({
        shipmentLegId: LEG_ID,
        newPlannedDepartureAt: "2026-08-04T00:00:00.000Z",
        newPlannedArrivalAt: "2026-08-05T00:00:00.000Z",
        reason: "",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "dispatcher",
      }),
    );
  });
});
