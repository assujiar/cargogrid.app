import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomerEpod, CustomerEpodMutationError, type CustomerEpodMutationRpcClient } from "./customer-epod.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const CAPTURE_ID = "523e4567-e89b-12d3-a456-426614174000";

const AVAILABLE_ROW = {
  shipment_order_id: SHIPMENT_ID,
  epod_status: "available",
  epod_capture_id: CAPTURE_ID,
  receiver_name: "Jane Receiver",
  captured_at: "2026-08-16T02:00:00.000Z",
  server_received_at: "2026-08-16T02:00:05.000Z",
  files: [{ fileId: "723e4567-e89b-12d3-a456-426614174000", role: "signature", originalFilename: "signature.png", mimeType: "image/png", sizeBytes: 20480 }],
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerEpodMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerEpodMutationRpcClient;
  return { client, calls };
}

describe("getCustomerEpod", () => {
  test("maps a single-object response and passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: AVAILABLE_ROW, error: null });
    const result = await getCustomerEpod(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID);
    assert.equal(result.epodStatus, "available");
    assert.equal(result.files.length, 1);
    assert.deepEqual(calls[0], {
      fn: "get_customer_epod",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_shipment_order_id: SHIPMENT_ID },
    });
  });

  test("also accepts an array-wrapped response (PostgREST array shape), taking the first row", async () => {
    const { client } = fakeRpcClient({ data: [AVAILABLE_ROW], error: null });
    const result = await getCustomerEpod(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID);
    assert.equal(result.epodCaptureId, CAPTURE_ID);
  });

  test("classifies record_not_found (anti-enumeration -- same code for nonexistent and out-of-scope)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted shipment order exists for x" } });
    await assert.rejects(
      () => getCustomerEpod(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerEpodMutationError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("classifies actor_identity_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actor_identity_mismatch: session identity does not match the claimed actor" } });
    await assert.rejects(
      () => getCustomerEpod(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerEpodMutationError);
        assert.equal(err.code, "actor_identity_mismatch");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => getCustomerEpod(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerEpodMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });

  test("throws mutation_failed when the RPC returns no row at all", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(
      () => getCustomerEpod(client, TENANT_ID, ACTOR_ID, SHIPMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerEpodMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
