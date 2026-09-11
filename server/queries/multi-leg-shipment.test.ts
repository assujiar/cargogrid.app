import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listShipmentLegs,
  listShipmentLegStops,
  getShipmentLegCargoAllocation,
  listShipmentLegCustodyEvents,
  getShipmentLegNetworkState,
  MultiLegShipmentQueryError,
} from "./multi-leg-shipment.ts";
import type { MultiLegShipmentQueryTableClient } from "./multi-leg-shipment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "423e4567-e89b-12d3-a456-426614174000";
const ALLOCATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const CUSTODY_EVENT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(
  responses: Record<string, { data: unknown; error: { message: string } | null }>,
  capture?: { calls: { fn: string; args: Record<string, unknown> }[] },
): MultiLegShipmentQueryTableClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture?.calls.push({ fn, args });
      return responses[fn] ?? { data: null, error: { message: `no mock response for ${fn}` } };
    },
  } as unknown as MultiLegShipmentQueryTableClient;
}

describe("listShipmentLegs", () => {
  test("calls list_shipment_legs with the shipment order and actor id, maps rows ordered by sequence_no", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient(
      {
        list_shipment_legs: {
          data: [
            {
              id: LEG_ID,
              tenant_id: TENANT_ID,
              shipment_order_id: SHIPMENT_ID,
              sequence_no: 1,
              idempotency_key: "idem-1",
              mode: "land",
              leg_status: "planned",
              is_legacy_compat: false,
              carrier_master_id: null,
              planned_departure_at: null,
              planned_arrival_at: null,
              actual_departure_at: null,
              actual_arrival_at: null,
              owner_user_id: null,
              record_version: 1,
              created_by: null,
              created_at: "2026-07-29T00:00:00.000Z",
              updated_at: "2026-07-29T00:00:00.000Z",
            },
          ],
          error: null,
        },
      },
      capture,
    );
    const legs = await listShipmentLegs(client, SHIPMENT_ID, ACTOR_ID);
    assert.deepEqual(capture.calls[0], { fn: "list_shipment_legs", args: { p_shipment_order_id: SHIPMENT_ID, p_actor_auth_user_id: ACTOR_ID } });
    assert.equal(legs.length, 1);
    assert.equal(legs[0]?.sequenceNo, 1);
  });

  test("surfaces a real query error as MultiLegShipmentQueryError", async () => {
    const client = fakeRpcClient({ list_shipment_legs: { data: null, error: { message: "connection reset" } } });
    await assert.rejects(() => listShipmentLegs(client, SHIPMENT_ID, ACTOR_ID), MultiLegShipmentQueryError);
  });
});

describe("listShipmentLegStops", () => {
  test("calls get_shipment_leg_stops and maps the GeoJSON projection", async () => {
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "get_shipment_leg_stops");
        assert.equal(args.p_shipment_leg_id, LEG_ID);
        return {
          data: [
            {
              id: LEG_ID,
              tenant_id: TENANT_ID,
              shipment_leg_id: LEG_ID,
              stop_sequence: 1,
              stop_type: "pickup",
              location_name: "Jakarta Warehouse",
              address: null,
              location_geojson: { type: "Point", coordinates: [106.8456, -6.2088] },
              planned_at: null,
              actual_at: null,
              stop_status: "pending",
              record_version: 1,
              created_at: "2026-07-29T00:00:00.000Z",
              updated_at: "2026-07-29T00:00:00.000Z",
            },
          ],
          error: null,
        };
      },
    } as unknown as MultiLegShipmentQueryTableClient;
    const stops = await listShipmentLegStops(client, LEG_ID);
    assert.equal(stops.length, 1);
    assert.equal(stops[0]?.longitude, 106.8456);
  });
});

describe("getShipmentLegCargoAllocation", () => {
  test("calls get_shipment_leg_cargo_allocation with the leg and actor id, maps the single row", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient(
      {
        get_shipment_leg_cargo_allocation: {
          data: [
            {
              id: ALLOCATION_ID,
              tenant_id: TENANT_ID,
              shipment_leg_id: LEG_ID,
              allocated_quantity: 10,
              allocated_weight_kg: 500,
              allocated_volume_cbm: 2.5,
              record_version: 1,
              created_by: "rep",
              created_at: "2026-07-29T00:00:00.000Z",
              updated_at: "2026-07-29T00:00:00.000Z",
            },
          ],
          error: null,
        },
      },
      capture,
    );
    const allocation = await getShipmentLegCargoAllocation(client, LEG_ID, ACTOR_ID);
    assert.deepEqual(capture.calls[0], { fn: "get_shipment_leg_cargo_allocation", args: { p_shipment_leg_id: LEG_ID, p_actor_auth_user_id: ACTOR_ID } });
    assert.equal(allocation?.allocatedQuantity, 10);
  });

  test("returns null (never an error) when no allocation exists yet", async () => {
    const client = fakeRpcClient({ get_shipment_leg_cargo_allocation: { data: [], error: null } });
    const allocation = await getShipmentLegCargoAllocation(client, LEG_ID, ACTOR_ID);
    assert.equal(allocation, null);
  });

  test("wraps a query error", async () => {
    const client = fakeRpcClient({ get_shipment_leg_cargo_allocation: { data: null, error: { message: "boom" } } });
    await assert.rejects(() => getShipmentLegCargoAllocation(client, LEG_ID, ACTOR_ID), MultiLegShipmentQueryError);
  });
});

describe("listShipmentLegCustodyEvents", () => {
  test("calls list_shipment_leg_custody_events with the leg and actor id, maps every row", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient(
      {
        list_shipment_leg_custody_events: {
          data: [
            {
              id: CUSTODY_EVENT_ID,
              tenant_id: TENANT_ID,
              shipment_leg_id: LEG_ID,
              sequence_no: 1,
              event_type: "custody_transfer",
              from_party_snapshot: null,
              to_party_snapshot: { name: "Driver A" },
              occurred_at: "2026-07-29T00:00:00.000Z",
              evidence: null,
              recorded_by: "rep",
              created_at: "2026-07-29T00:00:00.000Z",
            },
          ],
          error: null,
        },
      },
      capture,
    );
    const events = await listShipmentLegCustodyEvents(client, LEG_ID, ACTOR_ID);
    assert.deepEqual(capture.calls[0], { fn: "list_shipment_leg_custody_events", args: { p_shipment_leg_id: LEG_ID, p_actor_auth_user_id: ACTOR_ID } });
    assert.equal(events.length, 1);
    assert.equal(events[0]?.eventType, "custody_transfer");
  });

  test("returns an empty array, not an error, for a leg with no custody events yet", async () => {
    const client = fakeRpcClient({ list_shipment_leg_custody_events: { data: [], error: null } });
    assert.deepEqual(await listShipmentLegCustodyEvents(client, LEG_ID, ACTOR_ID), []);
  });
});

describe("getShipmentLegNetworkState", () => {
  test("parses the returned aggregate state", async () => {
    const client = {
      async rpc() {
        return { data: "in_progress", error: null };
      },
    } as unknown as MultiLegShipmentQueryTableClient;
    const state = await getShipmentLegNetworkState(client, SHIPMENT_ID);
    assert.equal(state, "in_progress");
  });
});
