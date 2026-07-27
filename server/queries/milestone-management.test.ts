import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getShipmentMilestoneTimeline,
  getShipmentMilestoneProjection,
  listMilestoneCodes,
  MilestoneManagementQueryError,
  type MilestoneManagementQueryRpcClient,
  type MilestoneManagementQueryTableClient,
} from "./milestone-management.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "523e4567-e89b-12d3-a456-426614174000";

const EVENT_ROW = {
  id: EVENT_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  milestone_code: "picked_up",
  event_time: "2026-07-27T08:00:00.000Z",
  received_time: "2026-07-27T08:05:00.000Z",
  location: null,
  source: "manual",
  reason: null,
  corrects_event_id: null,
  idempotency_key: "idem-1",
  sequence_no: 1,
  created_by: "rep",
  created_at: "2026-07-27T08:05:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): MilestoneManagementQueryRpcClient {
  return { rpc: () => Promise.resolve(response) } as unknown as MilestoneManagementQueryRpcClient;
}

describe("getShipmentMilestoneTimeline", () => {
  test("maps every row in the returned array", async () => {
    const client = fakeRpcClient({ data: [EVENT_ROW], error: null });
    const timeline = await getShipmentMilestoneTimeline(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(timeline.length, 1);
    assert.equal(timeline[0]?.milestoneCode, "picked_up");
  });

  test("returns an empty array (never an error) for a shipment with no events yet", async () => {
    const client = fakeRpcClient({ data: [], error: null });
    const timeline = await getShipmentMilestoneTimeline(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(timeline, []);
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getShipmentMilestoneTimeline(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof MilestoneManagementQueryError,
    );
  });
});

describe("getShipmentMilestoneProjection", () => {
  test("maps a real row", async () => {
    const client = fakeRpcClient({
      data: {
        shipment_order_id: SHIPMENT_ID,
        tenant_id: TENANT_ID,
        last_milestone_code: "picked_up",
        last_milestone_event_time: "2026-07-27T08:00:00.000Z",
        last_milestone_received_time: "2026-07-27T08:05:00.000Z",
        current_eta: null,
        current_location: null,
        is_delayed: false,
        event_count: 1,
        record_version: 1,
        updated_at: "2026-07-27T08:05:00.000Z",
      },
      error: null,
    });
    const projection = await getShipmentMilestoneProjection(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(projection?.lastMilestoneCode, "picked_up");
  });

  test("returns null (never an error) when no event has ever been ingested", async () => {
    const client = fakeRpcClient({ data: null, error: null });
    const projection = await getShipmentMilestoneProjection(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(projection, null);
  });

  test("wraps an rpc error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getShipmentMilestoneProjection(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => err instanceof MilestoneManagementQueryError,
    );
  });
});

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): MilestoneManagementQueryTableClient {
  return {
    from: () => ({
      select: () => ({
        order: () => Promise.resolve(response),
      }),
    }),
  } as unknown as MilestoneManagementQueryTableClient;
}

describe("listMilestoneCodes", () => {
  test("maps every row in the returned array", async () => {
    const client = fakeTableClient({
      data: [{ code: "picked_up", name: "Picked Up", category: "pickup", is_customer_visible: true, affects_eta: false, is_terminal: false, registered_by: "tester", created_at: "2026-07-27T00:00:00.000Z" }],
      error: null,
    });
    const codes = await listMilestoneCodes(client);
    assert.equal(codes.length, 1);
    assert.equal(codes[0]?.code, "picked_up");
  });

  test("returns an empty array (never an error) when nothing is registered yet", async () => {
    const client = fakeTableClient({ data: [], error: null });
    const codes = await listMilestoneCodes(client);
    assert.deepEqual(codes, []);
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => listMilestoneCodes(client), (err: unknown) => err instanceof MilestoneManagementQueryError);
  });
});
