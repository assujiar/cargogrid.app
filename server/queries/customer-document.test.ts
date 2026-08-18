import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listCustomerDocuments, CustomerDocumentQueryError, type CustomerDocumentQueryClient } from "./customer-document.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const DOCUMENT_ID = "423e4567-e89b-12d3-a456-426614174000";

const DOCUMENT_ROW = {
  document_id: DOCUMENT_ID,
  source_module: "quote_request",
  source_entity_id: ACCOUNT_ID,
  document_type: "quote_request_attachment",
  original_filename: "cargo-photo.jpg",
  mime_type: "image/jpeg",
  size_bytes: 204800,
  malware_scan_status: "clean",
  account_id: ACCOUNT_ID,
  created_at: "2026-08-16T02:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerDocumentQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerDocumentQueryClient;
  return { client, calls };
}

describe("listCustomerDocuments", () => {
  test("defaults every filter/cursor to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [DOCUMENT_ROW], error: null });
    const result = await listCustomerDocuments(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0], {
      fn: "list_customer_documents",
      args: {
        p_tenant_id: TENANT_ID,
        p_actor_auth_user_id: ACTOR_ID,
        p_account_id: null,
        p_shipment_order_id: null,
        p_source_module: null,
        p_date_from: null,
        p_date_to: null,
        p_cursor_created_at: null,
        p_cursor_id: null,
        p_limit: 50,
      },
    });
  });

  test("forwards every filter and cursor override", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerDocuments(client, TENANT_ID, ACTOR_ID, {
      accountId: ACCOUNT_ID,
      shipmentOrderId: SHIPMENT_ID,
      sourceModule: "epod",
      dateFrom: "2026-08-01T00:00:00.000Z",
      dateTo: "2026-08-16T00:00:00.000Z",
      cursorCreatedAt: "2026-08-16T00:00:00.000Z",
      cursorId: DOCUMENT_ID,
      limit: 10,
    });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: ACCOUNT_ID,
      p_shipment_order_id: SHIPMENT_ID,
      p_source_module: "epod",
      p_date_from: "2026-08-01T00:00:00.000Z",
      p_date_to: "2026-08-16T00:00:00.000Z",
      p_cursor_created_at: "2026-08-16T00:00:00.000Z",
      p_cursor_id: DOCUMENT_ID,
      p_limit: 10,
    });
  });

  test("returns an empty array (never throws) for a deny-by-default response, including a recognized-but-unbacked sourceModule", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await listCustomerDocuments(client, TENANT_ID, ACTOR_ID, { sourceModule: "invoice" });
    assert.deepEqual(result, []);
  });

  test("classifies invalid_source_module", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_source_module: not_a_real_source is not a recognized document source module" } });
    await assert.rejects(
      () => listCustomerDocuments(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentQueryError);
        assert.equal(err.code, "invalid_source_module");
        return true;
      },
    );
  });

  test("classifies invalid_date_range", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_date_range: p_date_to cannot be before p_date_from" } });
    await assert.rejects(
      () => listCustomerDocuments(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentQueryError);
        assert.equal(err.code, "invalid_date_range");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as query_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => listCustomerDocuments(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });
});
