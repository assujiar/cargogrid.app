import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getShipmentLegEtaProjection, MilestoneExceptionTelemetryQueryError, type MilestoneExceptionTelemetryQueryClient } from "./milestone-exception-telemetry.ts";

const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): MilestoneExceptionTelemetryQueryClient {
  return { rpc: async () => response } as unknown as MilestoneExceptionTelemetryQueryClient;
}

describe("getShipmentLegEtaProjection", () => {
  test("parses a scalar composite-type response", async () => {
    const client = fakeRpcClient({
      data: {
        shipment_leg_id: LEG_ID,
        computable: true,
        reason: null,
        position_status: "healthy",
        remaining_distance_km: 42.5,
        estimated_arrival_at: "2026-08-03T12:00:00.000Z",
        planned_arrival_at: "2026-08-03T10:00:00.000Z",
        delay_minutes: 120,
        downstream_leg_count: 2,
      },
      error: null,
    });
    const projection = await getShipmentLegEtaProjection(client, LEG_ID, ACTOR_ID);
    assert.equal(projection.computable, true);
    assert.equal(projection.downstreamLegCount, 2);
  });

  test("throws on an insufficient_authority rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
    await assert.rejects(() => getShipmentLegEtaProjection(client, LEG_ID, ACTOR_ID), MilestoneExceptionTelemetryQueryError);
  });

  test("throws when no row is returned", async () => {
    const client = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => getShipmentLegEtaProjection(client, LEG_ID, ACTOR_ID), MilestoneExceptionTelemetryQueryError);
  });
});
