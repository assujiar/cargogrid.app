import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFilesForTenant, listDocumentTypes, FileLookupError, DocumentTypeLookupError, type FileLookupClient, type DocumentTypeLookupClient } from "./document.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "523e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "623e4567-e89b-12d3-a456-426614174000";
const VERSION_GROUP_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeFileClient(response: { data: unknown[] | null; error: { message: string } | null }): FileLookupClient {
  return {
    from(table) {
      assert.equal(table, "files");
      return {
        select(columns) {
          assert.equal(columns, "*");
          return {
            async eq(column, value) {
              assert.equal(column, "tenant_id");
              assert.equal(value, TENANT_ID);
              return response;
            },
          };
        },
      };
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
    const files = await listFilesForTenant(client, TENANT_ID);
    assert.equal(files.length, 1);
    assert.equal(files[0]?.malwareScanStatus, "clean");
  });

  test("wraps a database error into a typed error", async () => {
    const client = fakeFileClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listFilesForTenant(client, TENANT_ID), FileLookupError);
  });

  test("returns an empty array rather than throwing when there is nothing to see", async () => {
    const client = fakeFileClient({ data: [], error: null });
    const files = await listFilesForTenant(client, TENANT_ID);
    assert.deepEqual(files, []);
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
