import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  addShipmentLeg,
  confirmShipmentLegNetwork,
  transitionShipmentLeg,
  recordShipmentLegCustodyEvent,
  MultiLegShipmentMutationError,
  type MultiLegShipmentMutationRpcClient,
} from "./multi-leg-shipment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: MultiLegShipmentMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as MultiLegShipmentMutationRpcClient;
  return { client, calls };
}

const LEG_ROW = {
  id: LEG_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  sequence_no: 1,
  idempotency_key: "idem-leg-1",
  mode: "land",
  leg_status: "planned",
  is_legacy_compat: false,
  carrier_master_id: null,
  planned_departure_at: null,
  planned_arrival_at: null,
  actual_departure_at: null,
  actual_arrival_at: null,
  owner_user_id: ACTOR_ID,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-29T00:00:00.000Z",
  updated_at: "2026-07-29T00:00:00.000Z",
};

describe("addShipmentLeg", () => {
  test("calls add_shipment_leg with snake_case args and parses the result", async () => {
    const { client, calls } = fakeRpcClient({ data: LEG_ROW, error: null });
    const leg = await addShipmentLeg(client, {
      shipmentOrderId: SHIPMENT_ID,
      idempotencyKey: "idem-leg-1",
      sequenceNo: 1,
      mode: "land",
      carrierMasterId: null,
      plannedDepartureAt: null,
      plannedArrivalAt: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(leg.sequenceNo, 1);
    assert.equal(calls[0]?.fn, "add_shipment_leg");
    assert.equal(calls[0]?.args.p_sequence_no, 1);
  });

  test("classifies a leg_sequence_duplicate error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "leg_sequence_duplicate: sequence 1 is already used" } });
    await assert.rejects(
      () =>
        addShipmentLeg(client, {
          shipmentOrderId: SHIPMENT_ID,
          idempotencyKey: "idem-leg-2",
          sequenceNo: 1,
          mode: "land",
          carrierMasterId: null,
          plannedDepartureAt: null,
          plannedArrivalAt: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof MultiLegShipmentMutationError && error.code === "leg_sequence_duplicate",
    );
  });

  test("classifies an unrecognized error message as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_postgres_error" } });
    await assert.rejects(
      () =>
        addShipmentLeg(client, {
          shipmentOrderId: SHIPMENT_ID,
          idempotencyKey: "idem-leg-3",
          sequenceNo: 1,
          mode: "land",
          carrierMasterId: null,
          plannedDepartureAt: null,
          plannedArrivalAt: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof MultiLegShipmentMutationError && error.code === "mutation_failed",
    );
  });
});

describe("confirmShipmentLegNetwork", () => {
  test("classifies a network_sequence_gap error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "network_sequence_gap: legs must form a contiguous sequence" } });
    await assert.rejects(
      () => confirmShipmentLegNetwork(client, { shipmentOrderId: SHIPMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof MultiLegShipmentMutationError && error.code === "network_sequence_gap",
    );
  });
});

describe("transitionShipmentLeg", () => {
  test("classifies a network_not_confirmed error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "network_not_confirmed: leg network must be confirmed before dispatch" } });
    await assert.rejects(
      () => transitionShipmentLeg(client, { shipmentLegId: LEG_ID, toStatus: "dispatched", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof MultiLegShipmentMutationError && error.code === "network_not_confirmed",
    );
  });

  test("classifies an invalid_leg_status_transition error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_leg_status_transition: leg cannot move from dispatched to completed" } });
    await assert.rejects(
      () => transitionShipmentLeg(client, { shipmentLegId: LEG_ID, toStatus: "completed", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof MultiLegShipmentMutationError && error.code === "invalid_leg_status_transition",
    );
  });
});

describe("recordShipmentLegCustodyEvent", () => {
  test("classifies a to_party_required error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "to_party_required: a custody event must name the party" } });
    await assert.rejects(
      () =>
        recordShipmentLegCustodyEvent(client, {
          shipmentLegId: LEG_ID,
          eventType: "custody_transfer",
          fromPartySnapshot: null,
          toPartySnapshot: {},
          occurredAt: "2026-07-29T00:00:00.000Z",
          evidence: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof MultiLegShipmentMutationError && error.code === "to_party_required",
    );
  });
});
