import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomerQuoteRequest, listCustomerQuoteRequests, listCustomerQuoteRequestFiles, CustomerQuoteRequestQueryError, type CustomerQuoteRequestQueryClient } from "./customer-quote-request.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_auth_user_id: ACTOR_ID,
  status: "draft",
  cargo_description: null,
  origin: {},
  destination: {},
  service_type: null,
  requested_pickup_date: null,
  requested_delivery_date: null,
  notes: null,
  idempotency_key: null,
  submitted_idempotency_key: null,
  linked_quotation_id: null,
  record_version: 1,
  created_by: ACTOR_ID,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  submitted_at: null,
  cancelled_at: null,
  cancelled_reason: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerQuoteRequestQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerQuoteRequestQueryClient;
  return { client, calls };
}

describe("getCustomerQuoteRequest", () => {
  test("maps the returned row and passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await getCustomerQuoteRequest(client, TENANT_ID, REQUEST_ID, ACTOR_ID);
    assert.equal(result.id, REQUEST_ID);
    assert.deepEqual(calls[0], {
      fn: "get_customer_quote_request",
      args: { p_tenant_id: TENANT_ID, p_request_id: REQUEST_ID, p_actor_auth_user_id: ACTOR_ID },
    });
  });

  test("classifies record_not_found (anti-enumeration -- same code for nonexistent and out-of-scope)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted quote request exists for x" } });
    await assert.rejects(
      () => getCustomerQuoteRequest(client, TENANT_ID, REQUEST_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as query_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => getCustomerQuoteRequest(client, TENANT_ID, REQUEST_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });
});

describe("listCustomerQuoteRequests", () => {
  test("defaults cursor to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await listCustomerQuoteRequests(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: null,
      p_status: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("forwards account/status filters and cursor overrides", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerQuoteRequests(client, TENANT_ID, ACTOR_ID, { accountId: ACCOUNT_ID, status: "submitted", cursorUpdatedAt: "2026-08-16T00:00:00.000Z", cursorId: REQUEST_ID, limit: 10 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: ACCOUNT_ID,
      p_status: "submitted",
      p_cursor_updated_at: "2026-08-16T00:00:00.000Z",
      p_cursor_id: REQUEST_ID,
      p_limit: 10,
    });
  });

  test("returns an empty array (never throws) for a deny-by-default response", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerQuoteRequests(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});

describe("listCustomerQuoteRequestFiles", () => {
  test("maps attachment metadata rows", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ id: REQUEST_ID, original_filename: "cargo.jpg", mime_type: "image/jpeg", size_bytes: 1024, malware_scan_status: "clean", uploaded_by_auth_user_id: ACTOR_ID, created_at: "2026-08-16T00:00:00.000Z" }],
      error: null,
    });
    const result = await listCustomerQuoteRequestFiles(client, TENANT_ID, REQUEST_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.equal(result[0]?.malwareScanStatus, "clean");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_request_id: REQUEST_ID, p_actor_auth_user_id: ACTOR_ID });
  });

  test("returns an empty array for an out-of-scope/nonexistent request", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerQuoteRequestFiles(client, TENANT_ID, REQUEST_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});
