import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { issueShipmentTrackingToken, revokeShipmentTrackingToken, PublicTrackingMutationError, type PublicTrackingMutationRpcClient } from "./public-tracking.ts";

const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const TOKEN_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: PublicTrackingMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PublicTrackingMutationRpcClient;
  return { client, calls };
}

describe("issueShipmentTrackingToken", () => {
  test("calls issue_shipment_tracking_token with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({
      data: { token_id: TOKEN_ID, raw_token: "a".repeat(64), expires_at: "2026-08-27T09:00:00.000Z", shipment_order_id: SHIPMENT_ID },
      error: null,
    });
    const issued = await issueShipmentTrackingToken(client, { shipmentOrderId: SHIPMENT_ID, validityDays: 30, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "issue_shipment_tracking_token");
    assert.deepEqual(calls[0]?.args, { p_shipment_order_id: SHIPMENT_ID, p_validity_days: 30, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(issued.tokenId, TOKEN_ID);
  });

  test("classifies tracking_invalid_validity_days", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "tracking_invalid_validity_days: validity_days must be positive" } });
    await assert.rejects(
      () => issueShipmentTrackingToken(client, { shipmentOrderId: SHIPMENT_ID, validityDays: 30, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof PublicTrackingMutationError);
        assert.equal(err.code, "tracking_invalid_validity_days");
        return true;
      },
    );
  });
});

describe("revokeShipmentTrackingToken", () => {
  test("calls revoke_shipment_tracking_token with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({
      data: {
        id: TOKEN_ID,
        tenant_id: TENANT_ID,
        shipment_order_id: SHIPMENT_ID,
        status: "revoked",
        expires_at: "2026-08-27T09:00:00.000Z",
        revoked_at: "2026-07-28T10:00:00.000Z",
        revoked_reason: "compromised link",
        created_by: "rep",
        created_at: "2026-07-28T09:00:00.000Z",
      },
      error: null,
    });
    const token = await revokeShipmentTrackingToken(client, { shipmentOrderId: SHIPMENT_ID, reason: "compromised link", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "revoke_shipment_tracking_token");
    assert.deepEqual(calls[0]?.args, { p_shipment_order_id: SHIPMENT_ID, p_reason: "compromised link", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(token.status, "revoked");
  });

  test("classifies tracking_no_active_token", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "tracking_no_active_token: shipment order has no active tracking token" } });
    await assert.rejects(
      () => revokeShipmentTrackingToken(client, { shipmentOrderId: SHIPMENT_ID, reason: "compromised link", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof PublicTrackingMutationError);
        assert.equal(err.code, "tracking_no_active_token");
        return true;
      },
    );
  });
});
