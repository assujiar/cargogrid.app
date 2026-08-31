import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFilesForTenant, listDocumentTypes, FileLookupError, DocumentTypeLookupError, type FileLookupClient, type DocumentTypeLookupClient } from "./document.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "523e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "623e4567-e89b-12d3-a456-426614174000";
const VERSION_GROUP_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

// ISS-2026-172(b): the client now speaks RPC, not raw table reads. The helper asserts the
// exact call shape, so a regression that reverts to `.from("files")` fails to type-check
// AND fails here, rather than silently going back to an unlogged read path.
function fakeFileClient(
  response: { data: unknown; error: { message: string } | null },
  onArgs?: (args: Record<string, unknown>) => void,
): FileLookupClient {
  return {
    async rpc(fn, args) {
      assert.equal(fn, "list_files_for_tenant");
      onArgs?.(args);
      return response;
    },
  };
}

function fakeDocumentTypeClient(response: { data: unknown[] | null; error: { message: string } | null }): DocumentTypeLookupClient {
  return {
    from(table) {
      assert.equal(table, "document_types");
      return {
        select(columns) {
          assert.equal(columns, "*");
          return Promise.resolve(response);
        },
      };
    },
  };
}

describe("listFilesForTenant", () => {
  test("maps every row the caller's RLS grants visibility into", async () => {
    const client = fakeFileClient({
      data: [
        {
          id: FILE_ID,
          tenant_id: TENANT_ID,
          document_type_code: "contract",
          config_version_id: VERSION_ID,
          record_type: "shipment",
          record_id: RECORD_ID,
          classification: "confidential",
          original_filename: "msa.pdf",
          mime_type: "application/pdf",
          size_bytes: 204800,
          storage_path: `tenant/${TENANT_ID}/contract/${FILE_ID}`,
          malware_scan_status: "clean",
          malware_scan_completed_at: "2026-07-19T00:00:00.000Z",
          malware_scan_provider_ref: "provider-ref-1",
          version_group_id: VERSION_GROUP_ID,
          version_number: 1,
          is_latest_version: true,
          lifecycle_status: "active",
          legal_hold: false,
          legal_hold_reason: null,
          deleted_at: null,
          uploaded_by_auth_user_id: ACTOR_ID,
          shared_org_unit_ids: [],
          customer_account_ref: null,
          idempotency_key: "idem-msa-upload-1",
          created_at: "2026-07-19T00:00:00.000Z",
          updated_at: "2026-07-19T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const files = await listFilesForTenant(client, TENANT_ID, ACTOR_ID);
    assert.equal(files.rows.length, 1);
    assert.equal(files.rows[0]?.malwareScanStatus, "clean");
    // ISS-2026-238: one row is nowhere near the cap, so no truncation warning.
    assert.equal(files.truncated, false);
    // HDN-377 (Storage and Signed URL Audit) regression: storagePath must never appear
    // on a FileSummary, even if the underlying row somehow carried it.
    assert.equal("storagePath" in (files.rows[0] ?? {}), false);
  });

  test("passes the tenant, the actor and the correlation id through to the logged RPC", () => {
    // ISS-2026-172(b): the actor argument is what makes the read attributable in
    // app.file_access_logs. Dropping it would still compile and still return rows, and the
    // log would silently lose its subject -- so the call shape is asserted explicitly.
    let seen: Record<string, unknown> | null = null;
    const client = fakeFileClient({ data: [], error: null }, (args) => {
      seen = args;
    });
    return listFilesForTenant(client, TENANT_ID, ACTOR_ID, RECORD_ID).then(() => {
      assert.deepEqual(seen, {
        p_tenant_id: TENANT_ID,
        p_actor_auth_user_id: ACTOR_ID,
        p_correlation_id: RECORD_ID,
        // ISS-2026-238: the cap is part of the call shape now. Asserted rather than assumed --
        // this listing writes an app.file_access_logs row per row it returns, so an
        // accidentally-dropped limit would flood the audit trail, not just the payload.
        p_limit: 200,
      });
    });
  });

  test("defaults the correlation id to null rather than omitting it", () => {
    let seen: Record<string, unknown> | null = null;
    const client = fakeFileClient({ data: [], error: null }, (args) => {
      seen = args;
    });
    return listFilesForTenant(client, TENANT_ID, ACTOR_ID).then(() => {
      assert.equal((seen as unknown as Record<string, unknown>).p_correlation_id, null);
    });
  });

  test("rejects a non-array RPC result rather than coercing it", async () => {
    const client = fakeFileClient({ data: { not: "an array" }, error: null });
    await assert.rejects(() => listFilesForTenant(client, TENANT_ID, ACTOR_ID), FileLookupError);
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeFileClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listFilesForTenant(client, TENANT_ID, ACTOR_ID), FileLookupError);
  });

  test("returns an empty array rather than throwing when there is nothing to see", async () => {
    const client = fakeFileClient({ data: [], error: null });
    const files = await listFilesForTenant(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(files.rows, []);
    assert.equal(files.truncated, false);
  });
});

describe("listDocumentTypes", () => {
  test("maps every row of the registry", async () => {
    const client = fakeDocumentTypeClient({
      data: [
        { code: "contract", name: "Contract", owner_primitive_code: "DOC", registered_by: "platform-core-foundation", created_at: "2026-07-19T00:00:00.000Z" },
        { code: "epod", name: "Electronic Proof of Delivery", owner_primitive_code: "DOC", registered_by: "platform-core-foundation", created_at: "2026-07-19T00:00:00.000Z" },
      ],
      error: null,
    });
    const types = await listDocumentTypes(client);
    assert.equal(types.length, 2);
    assert.equal(types[1]?.code, "epod");
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeDocumentTypeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listDocumentTypes(client), DocumentTypeLookupError);
  });
});
