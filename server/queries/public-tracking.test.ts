import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { lookupPublicShipmentTracking, getActiveShipmentTrackingToken, PublicTrackingQueryError, type PublicTrackingQueryClient } from "./public-tracking.ts";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: PublicTrackingQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PublicTrackingQueryClient;
  return { client, calls };
}

function fakeFromClient(response: { data: unknown; error: { message: string } | null }): {
  client: PublicTrackingQueryClient;
  calls: { table: string; eqs: [string, unknown][] }[];
} {
  const calls: { table: string; eqs: [string, unknown][] }[] = [];
  const client = {
    from(table: string) {
      const eqs: [string, unknown][] = [];
      const builder = {
        select() {
          return builder;
        },
        eq(column: string, value: unknown) {
          eqs.push([column, value]);
          return builder;
        },
        async maybeSingle() {
          calls.push({ table, eqs });
          return response;
        },
      };
      return builder;
    },
  } as unknown as PublicTrackingQueryClient;
  return { client, calls };
}

const OK_ROW = {
  lookup_status: "ok",
  shipment_number: "SHP-0001",
  status: "in_transit",
  mode: "sea",
  origin: "Jakarta",
  destination: "Surabaya",
  planned_delivery_at: "2026-08-05T00:00:00.000Z",
  current_eta: null,
  is_delayed: false,
  milestones: [],
  epod_available: false,
};

describe("lookupPublicShipmentTracking", () => {
  test("calls lookup_public_shipment_tracking with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: OK_ROW, error: null });
    const result = await lookupPublicShipmentTracking(client, { rawToken: "a".repeat(64), clientKey: "client-hash-1" });
    assert.equal(calls[0]?.fn, "lookup_public_shipment_tracking");
    assert.deepEqual(calls[0]?.args, { p_raw_token: "a".repeat(64), p_client_key: "client-hash-1" });
    assert.equal(result.lookupStatus, "ok");
  });

  test("resolves (never throws) for a not_found outcome -- callers branch on lookupStatus, not exceptions", async () => {
    const { client } = fakeRpcClient({ data: { ...OK_ROW, lookup_status: "not_found", shipment_number: null, status: null, mode: null, origin: null, destination: null, planned_delivery_at: null, epod_available: null }, error: null });
    const result = await lookupPublicShipmentTracking(client, { rawToken: "bad-token", clientKey: "client-hash-2" });
    assert.equal(result.lookupStatus, "not_found");
  });

  test("wraps a genuine RPC-level error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "tracking_client_key_required: a client_key is required" } });
    await assert.rejects(
      () => lookupPublicShipmentTracking(client, { rawToken: null, clientKey: "x" }),
      (err: unknown) => {
        assert.ok(err instanceof PublicTrackingQueryError);
        return true;
      },
    );
  });
});

describe("getActiveShipmentTrackingToken", () => {
  test("returns null when no active token exists", async () => {
    const { client, calls } = fakeFromClient({ data: null, error: null });
    const token = await getActiveShipmentTrackingToken(client, "323e4567-e89b-12d3-a456-426614174000");
    assert.equal(token, null);
    assert.equal(calls[0]?.table, "shipment_tracking_tokens");
    assert.deepEqual(calls[0]?.eqs, [
      ["shipment_order_id", "323e4567-e89b-12d3-a456-426614174000"],
      ["status", "active"],
    ]);
  });

  test("maps the active token row", async () => {
    const { client } = fakeFromClient({
      data: {
        id: "423e4567-e89b-12d3-a456-426614174000",
        tenant_id: "223e4567-e89b-12d3-a456-426614174000",
        shipment_order_id: "323e4567-e89b-12d3-a456-426614174000",
        status: "active",
        expires_at: "2026-08-27T09:00:00.000Z",
        revoked_at: null,
        revoked_reason: null,
        created_by: "rep",
        created_at: "2026-07-28T09:00:00.000Z",
      },
      error: null,
    });
    const token = await getActiveShipmentTrackingToken(client, "323e4567-e89b-12d3-a456-426614174000");
    assert.equal(token?.status, "active");
  });
});
