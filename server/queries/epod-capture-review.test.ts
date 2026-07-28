import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getEpodCaptureHistory, EpodCaptureReviewQueryError, type EpodCaptureReviewQueryClient } from "./epod-capture-review.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const CAPTURE_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: EpodCaptureReviewQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as EpodCaptureReviewQueryClient;
  return { client, calls };
}

const CAPTURE_ROW = {
  id: CAPTURE_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  milestone_event_id: null,
  version_group_id: CAPTURE_ID,
  version_number: 1,
  is_latest_version: true,
  status: "draft",
  receiver_name: null,
  receiver_position: null,
  signature_file_id: null,
  photo_file_ids: [],
  delivery_geog: null,
  captured_at: null,
  server_received_at: "2026-07-28T09:00:00.000Z",
  reviewed_by_auth_user_id: null,
  reviewed_at: null,
  review_notes: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("getEpodCaptureHistory", () => {
  test("calls get_epod_capture_history with the exact snake_case params and maps every version", async () => {
    const { client, calls } = fakeRpcClient({ data: [CAPTURE_ROW, { ...CAPTURE_ROW, version_number: 2, is_latest_version: false }], error: null });
    const history = await getEpodCaptureHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(calls[0]?.fn, "get_epod_capture_history");
    assert.deepEqual(calls[0]?.args, { p_shipment_order_id: SHIPMENT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(history.length, 2);
  });

  test("wraps an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
    await assert.rejects(
      () => getEpodCaptureHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof EpodCaptureReviewQueryError);
        return true;
      },
    );
  });

  test("rejects a non-array response", async () => {
    const { client } = fakeRpcClient({ data: {}, error: null });
    await assert.rejects(() => getEpodCaptureHistory(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID }));
  });
});
