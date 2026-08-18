import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { uploadCustomerQuoteRequestAttachment, CustomerQuoteRequestAttachmentMutationError, type CustomerQuoteRequestAttachmentMutationRpcClient } from "./customer-quote-request-attachment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "323e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const FILE_ROW = {
  id: FILE_ID,
  tenant_id: TENANT_ID,
  document_type_code: "quote_request_attachment",
  config_version_id: "623e4567-e89b-12d3-a456-426614174000",
  record_type: "customer_portal_quote_request",
  record_id: REQUEST_ID,
  classification: "internal",
  original_filename: "cargo.jpg",
  mime_type: "image/jpeg",
  size_bytes: 2048,
  storage_path: "tenant/x/quote_request_attachment/y",
  malware_scan_status: "pending",
  malware_scan_completed_at: null,
  malware_scan_provider_ref: null,
  version_group_id: "723e4567-e89b-12d3-a456-426614174000",
  version_number: 1,
  is_latest_version: true,
  lifecycle_status: "active",
  legal_hold: false,
  legal_hold_reason: null,
  deleted_at: null,
  uploaded_by_auth_user_id: ACTOR_ID,
  shared_org_unit_ids: [],
  customer_account_ref: null,
  idempotency_key: "attach-1",
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerQuoteRequestAttachmentMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerQuoteRequestAttachmentMutationRpcClient;
  return { client, calls };
}

describe("uploadCustomerQuoteRequestAttachment", () => {
  test("fixes documentTypeCode/recordType to this capability's own constants, forwards everything else", async () => {
    const { client, calls } = fakeRpcClient({ data: FILE_ROW, error: null });
    const result = await uploadCustomerQuoteRequestAttachment(client, {
      tenantId: TENANT_ID,
      requestId: REQUEST_ID,
      originalFilename: "cargo.jpg",
      mimeType: "image/jpeg",
      sizeBytes: 2048,
      idempotencyKey: "attach-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.recordId, REQUEST_ID);
    assert.deepEqual(calls[0], {
      fn: "initiate_file_upload",
      args: {
        p_tenant_id: TENANT_ID,
        p_document_type_code: "quote_request_attachment",
        p_record_type: "customer_portal_quote_request",
        p_record_id: REQUEST_ID,
        p_original_filename: "cargo.jpg",
        p_mime_type: "image/jpeg",
        p_size_bytes: 2048,
        p_classification: null,
        p_legal_hold: false,
        p_legal_hold_reason: null,
        p_shared_org_unit_ids: [],
        p_customer_account_ref: null,
        p_idempotency_key: "attach-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("classifies file_actor_unauthorized", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "file_actor_unauthorized: identity x lacks active membership in tenant y" } });
    await assert.rejects(
      () =>
        uploadCustomerQuoteRequestAttachment(client, {
          tenantId: TENANT_ID,
          requestId: REQUEST_ID,
          originalFilename: "cargo.jpg",
          mimeType: "image/jpeg",
          sizeBytes: 2048,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "x",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestAttachmentMutationError);
        assert.equal(err.code, "file_actor_unauthorized");
        return true;
      },
    );
  });

  test("classifies document_type_not_configured (a tenant must publish a definition first, standing PLT-128 precondition)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "document_type_not_configured: tenant x has not published a definition for document type quote_request_attachment" } });
    await assert.rejects(
      () =>
        uploadCustomerQuoteRequestAttachment(client, {
          tenantId: TENANT_ID,
          requestId: REQUEST_ID,
          originalFilename: "cargo.jpg",
          mimeType: "image/jpeg",
          sizeBytes: 2048,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "x",
        }),
      (err: unknown) => {
        assert.ok(err instanceof CustomerQuoteRequestAttachmentMutationError);
        assert.equal(err.code, "document_type_not_configured");
        return true;
      },
    );
  });
});
