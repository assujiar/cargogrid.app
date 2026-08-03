import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  reserveVehicleCapacity,
  consumeVehicleCapacityReservation,
  releaseVehicleCapacityReservation,
  CapacityUtilizationMutationError,
  type CapacityUtilizationMutationRpcClient,
} from "./capacity-utilization.ts";

const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CapacityUtilizationMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CapacityUtilizationMutationRpcClient;
  return { client, calls };
}

const RESERVATION_ROW = {
  id: RESERVATION_ID,
  tenant_id: "223e4567-e89b-12d3-a456-426614174000",
  shipment_leg_id: LEG_ID,
  vehicle_master_id: "423e4567-e89b-12d3-a456-426614174000",
  idempotency_key: "leg-1-reserve",
  requested_weight_kg: 1200,
  requested_volume_cbm: 8,
  window_start: "2026-08-03T00:00:00.000Z",
  window_end: "2026-08-04T00:00:00.000Z",
  status: "held",
  released_reason: null,
  record_version: 1,
  created_by: "dispatcher",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("reserveVehicleCapacity", () => {
  test("calls reserve_vehicle_capacity with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: RESERVATION_ROW, error: null });
    const reservation = await reserveVehicleCapacity(client, {
      shipmentLegId: LEG_ID,
      requestedWeightKg: 1200,
      requestedVolumeCbm: 8,
      idempotencyKey: "leg-1-reserve",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "dispatcher",
    });
    assert.equal(reservation.status, "held");
    assert.equal(calls[0]?.fn, "reserve_vehicle_capacity");
    assert.equal(calls[0]?.args.p_shipment_leg_id, LEG_ID);
    assert.equal(calls[0]?.args.p_idempotency_key, "leg-1-reserve");
  });

  test("classifies a capacity_exceeded error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "capacity_exceeded: vehicle weight capacity exceeded" } });
    await assert.rejects(
      () =>
        reserveVehicleCapacity(client, {
          shipmentLegId: LEG_ID,
          requestedWeightKg: 999999,
          requestedVolumeCbm: null,
          idempotencyKey: "leg-1-reserve",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "dispatcher",
        }),
      (error: unknown) => error instanceof CapacityUtilizationMutationError && error.code === "capacity_exceeded",
    );
  });

  test("classifies a vehicle_not_assigned error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "vehicle_not_assigned: leg has no current active vehicle resource assignment" } });
    await assert.rejects(
      () =>
        reserveVehicleCapacity(client, {
          shipmentLegId: LEG_ID,
          requestedWeightKg: null,
          requestedVolumeCbm: null,
          idempotencyKey: "leg-1-reserve",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "dispatcher",
        }),
      (error: unknown) => error instanceof CapacityUtilizationMutationError && error.code === "vehicle_not_assigned",
    );
  });

  test("rejects a negative requested weight before ever calling rpc (zod schema minimum)", async () => {
    const { client, calls } = fakeRpcClient({ data: RESERVATION_ROW, error: null });
    await assert.rejects(() =>
      reserveVehicleCapacity(client, {
        shipmentLegId: LEG_ID,
        requestedWeightKg: -1,
        requestedVolumeCbm: null,
        idempotencyKey: "leg-1-reserve",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "dispatcher",
      }),
    );
    assert.equal(calls.length, 0);
  });
});

describe("consumeVehicleCapacityReservation", () => {
  test("calls consume_vehicle_capacity_reservation with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...RESERVATION_ROW, status: "consumed", record_version: 2 }, error: null });
    const reservation = await consumeVehicleCapacityReservation(client, { reservationId: RESERVATION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "dispatcher" });
    assert.equal(reservation.status, "consumed");
    assert.equal(calls[0]?.fn, "consume_vehicle_capacity_reservation");
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });

  test("classifies a stale_version error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: reservation expected version 1 but found 2" } });
    await assert.rejects(
      () => consumeVehicleCapacityReservation(client, { reservationId: RESERVATION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "dispatcher" }),
      (error: unknown) => error instanceof CapacityUtilizationMutationError && error.code === "stale_version",
    );
  });

  test("classifies an invalid_transition error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: reservation is released -- only a held reservation may be consumed" } });
    await assert.rejects(
      () => consumeVehicleCapacityReservation(client, { reservationId: RESERVATION_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "dispatcher" }),
      (error: unknown) => error instanceof CapacityUtilizationMutationError && error.code === "invalid_transition",
    );
  });
});

describe("releaseVehicleCapacityReservation", () => {
  test("calls release_vehicle_capacity_reservation with snake_case args including reason", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...RESERVATION_ROW, status: "released", released_reason: "leg_completed", record_version: 2 }, error: null });
    const reservation = await releaseVehicleCapacityReservation(client, {
      reservationId: RESERVATION_ID,
      reason: "leg_completed",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "dispatcher",
    });
    assert.equal(reservation.status, "released");
    assert.equal(reservation.releasedReason, "leg_completed");
    assert.equal(calls[0]?.args.p_reason, "leg_completed");
  });

  test("rejects an empty reason before ever calling rpc (zod schema minimum)", async () => {
    const { client, calls } = fakeRpcClient({ data: RESERVATION_ROW, error: null });
    await assert.rejects(() =>
      releaseVehicleCapacityReservation(client, { reservationId: RESERVATION_ID, reason: "", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "dispatcher" }),
    );
    assert.equal(calls.length, 0);
  });
});
