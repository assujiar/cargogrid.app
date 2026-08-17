import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomerDocument, CustomerDocumentMutationError, type CustomerDocumentMutationRpcClient } from "./customer-document.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const DOCUMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";

const DOCUMENT_ROW = {
  document_id: DOCUMENT_ID,
  source_module: "epod",
  source_entity_id: ACCOUNT_ID,
  document_type: "epod_signature",
  original_filename: "signature.png",
  mime_type: "image/png",
  size_bytes: 20480,
  malware_scan_status: "clean",
  account_id: ACCOUNT_ID,
  created_at: "2026-08-16T02:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerDocumentMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerDocumentMutationRpcClient;
  return { client, calls };
}

describe("getCustomerDocument", () => {
  test("maps a single-object response and passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: DOCUMENT_ROW, error: null });
    const result = await getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID);
    assert.equal(result.sourceModule, "epod");
    assert.deepEqual(calls[0], {
      fn: "get_customer_document",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_document_id: DOCUMENT_ID },
    });
  });

  test("also accepts an array-wrapped response (PostgREST array shape), taking the first row", async () => {
    const { client } = fakeRpcClient({ data: [DOCUMENT_ROW], error: null });
    const result = await getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID);
    assert.equal(result.documentId, DOCUMENT_ID);
  });

  test("classifies document_not_found (anti-enumeration -- same code for nonexistent, out-of-scope, and unreferenced)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "document_not_found: no permitted document exists for x" } });
    await assert.rejects(
      () => getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentMutationError);
        assert.equal(err.code, "document_not_found");
        return true;
      },
    );
  });

  test("throws document_not_downloadable for a non-clean scan status even though the RPC call itself succeeded (migration design decision 5 -- the RPC never raises for this case, so the refusal is enforced HERE, after its own audit trail already committed)", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...DOCUMENT_ROW, malware_scan_status: "pending" }, error: null });
    await assert.rejects(
      () => getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentMutationError);
        assert.equal(err.code, "document_not_downloadable");
        return true;
      },
    );
    // The RPC really was called (and, on the real database, really did write
    // its own durable DENIED app.file_access_logs row) -- this function's own
    // throw happens strictly AFTER that call resolved successfully.
    assert.equal(calls.length, 1);
  });

  test("throws document_not_downloadable for an infected scan status", async () => {
    const { client } = fakeRpcClient({ data: { ...DOCUMENT_ROW, malware_scan_status: "infected" }, error: null });
    await assert.rejects(
      () => getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentMutationError);
        assert.equal(err.code, "document_not_downloadable");
        return true;
      },
    );
  });

  test("classifies a genuine RPC-level document_not_downloadable error message too (defensive -- current RPC behavior never raises this, but the classifier still recognizes the prefix)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "document_not_downloadable: document x has not cleared malware scanning (status pending)" } });
    await assert.rejects(
      () => getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentMutationError);
        assert.equal(err.code, "document_not_downloadable");
        return true;
      },
    );
  });

  test("classifies actor_identity_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actor_identity_mismatch: session identity does not match the claimed actor" } });
    await assert.rejects(
      () => getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentMutationError);
        assert.equal(err.code, "actor_identity_mismatch");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });

  test("throws mutation_failed when the RPC returns no row at all", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(
      () => getCustomerDocument(client, TENANT_ID, ACTOR_ID, DOCUMENT_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerDocumentMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
