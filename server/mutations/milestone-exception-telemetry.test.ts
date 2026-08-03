import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { rebaselineShipmentLegSchedule, MilestoneExceptionTelemetryMutationError, type MilestoneExceptionTelemetryMutationRpcClient } from "./milestone-exception-telemetry.ts";

const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: MilestoneExceptionTelemetryMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as MilestoneExceptionTelemetryMutationRpcClient;
  return { client, calls };
}

const LEG_ROW = {
  id: LEG_ID,
  tenant_id: "223e4567-e89b-12d3-a456-426614174000",
  shipment_order_id: "423e4567-e89b-12d3-a456-426614174000",
  sequence_no: 1,
  idempotency_key: "idem-leg-1",
  mode: "land",
  leg_status: "planned",
  is_legacy_compat: false,
  carrier_master_id: null,
  planned_departure_at: "2026-08-04T00:00:00.000Z",
  planned_arrival_at: "2026-08-05T00:00:00.000Z",
  actual_departure_at: null,
  actual_arrival_at: null,
  owner_user_id: null,
  record_version: 2,
  created_by: "dispatcher",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("rebaselineShipmentLegSchedule", () => {
  test("calls rebaseline_shipment_leg_schedule with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: LEG_ROW, error: null });
    const leg = await rebaselineShipmentLegSchedule(client, {
      shipmentLegId: LEG_ID,
      newPlannedDepartureAt: "2026-08-04T00:00:00.000Z",
      newPlannedArrivalAt: "2026-08-05T00:00:00.000Z",
      reason: "customer requested a later pickup window",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "dispatcher",
    });
    assert.equal(leg.plannedArrivalAt, "2026-08-05T00:00:00.000Z");
    assert.equal(calls[0]?.fn, "rebaseline_shipment_leg_schedule");
    assert.equal(calls[0]?.args.p_reason, "customer requested a later pickup window");
  });

  test("classifies a leg_not_unstarted error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "leg_not_unstarted: leg is dispatched, only a planned (unstarted) leg may be rebaselined" } });
    await assert.rejects(
      () =>
        rebaselineShipmentLegSchedule(client, {
          shipmentLegId: LEG_ID,
          newPlannedDepartureAt: "2026-08-04T00:00:00.000Z",
          newPlannedArrivalAt: "2026-08-05T00:00:00.000Z",
          reason: "attempt on a started leg",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "dispatcher",
        }),
      (error: unknown) => error instanceof MilestoneExceptionTelemetryMutationError && error.code === "leg_not_unstarted",
    );
  });

  test("rejects an empty reason before ever calling rpc (zod schema minimum)", async () => {
    const { client, calls } = fakeRpcClient({ data: LEG_ROW, error: null });
    await assert.rejects(() =>
      rebaselineShipmentLegSchedule(client, {
        shipmentLegId: LEG_ID,
        newPlannedDepartureAt: "2026-08-04T00:00:00.000Z",
        newPlannedArrivalAt: "2026-08-05T00:00:00.000Z",
        reason: "",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "dispatcher",
      }),
    );
    assert.equal(calls.length, 0);
  });
});
