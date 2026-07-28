import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createDocumentRequirementDraft,
  publishDocumentRequirementVersion,
  pinShipmentDocumentChecklist,
  linkDocumentToChecklistItem,
  reviewDocumentChecklistItem,
  uploadShipmentDocumentFile,
  DocumentRequirementMutationError,
  type DocumentRequirementMutationRpcClient,
} from "./document-requirement.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const DEFINITION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "623e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: DocumentRequirementMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as DocumentRequirementMutationRpcClient;
  return { client, calls };
}

const DEFINITION_ROW = {
  id: DEFINITION_ID,
  tenant_id: TENANT_ID,
  mode: null,
  service_type: null,
  applicable_status: "delivered",
  party: "carrier",
  document_type_code: "pod",
  criticality: "mandatory",
  status: "draft",
  supersedes_version_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

const ITEM_ROW = {
  id: ITEM_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  requirement_definition_id: DEFINITION_ID,
  party: "carrier",
  document_type_code: "pod",
  criticality: "mandatory",
  file_id: null,
  review_status: "pending",
  reviewed_by_auth_user_id: null,
  reviewed_at: null,
  review_notes: null,
  expires_at: null,
  pinned_at: "2026-07-28T09:00:00.000Z",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("createDocumentRequirementDraft", () => {
  test("calls create_document_requirement_draft with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: DEFINITION_ROW, error: null });
    const definition = await createDocumentRequirementDraft(client, {
      tenantId: TENANT_ID,
      mode: null,
      serviceType: null,
      applicableStatus: "delivered",
      party: "carrier",
      documentTypeCode: "pod",
      criticality: "mandatory",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "create_document_requirement_draft");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_mode: null,
      p_service_type: null,
      p_applicable_status: "delivered",
      p_party: "carrier",
      p_document_type_code: "pod",
      p_criticality: "mandatory",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(definition.status, "draft");
  });

  test("classifies insufficient_authority for an OPS:View-only actor", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:Create" } });
    await assert.rejects(
      () =>
        createDocumentRequirementDraft(client, {
          tenantId: TENANT_ID,
          mode: null,
          serviceType: null,
          applicableStatus: "delivered",
          party: "carrier",
          documentTypeCode: "pod",
          criticality: "mandatory",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "viewer",
        }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentRequirementMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishDocumentRequirementVersion", () => {
  test("calls publish_document_requirement_version with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...DEFINITION_ROW, status: "published" }, error: null });
    const definition = await publishDocumentRequirementVersion(client, {
      versionId: DEFINITION_ID,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "publish_document_requirement_version");
    assert.deepEqual(calls[0]?.args, {
      p_version_id: DEFINITION_ID,
      p_expected_version: 1,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(definition.status, "published");
  });

  test("classifies concurrent_modification on a stale expected version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "concurrent_modification: document requirement has moved" } });
    await assert.rejects(
      () => publishDocumentRequirementVersion(client, { versionId: DEFINITION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentRequirementMutationError);
        assert.equal(err.code, "concurrent_modification");
        return true;
      },
    );
  });
});

describe("pinShipmentDocumentChecklist", () => {
  test("calls pin_shipment_document_checklist and maps every pinned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [ITEM_ROW], error: null });
    const items = await pinShipmentDocumentChecklist(client, { shipmentOrderId: SHIPMENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "pin_shipment_document_checklist");
    assert.deepEqual(calls[0]?.args, { p_shipment_order_id: SHIPMENT_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(items.length, 1);
    assert.equal(items[0]?.reviewStatus, "pending");
  });
});

describe("linkDocumentToChecklistItem", () => {
  test("calls link_document_to_checklist_item with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...ITEM_ROW, file_id: FILE_ID }, error: null });
    const item = await linkDocumentToChecklistItem(client, { checklistItemId: ITEM_ID, fileId: FILE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "link_document_to_checklist_item");
    assert.deepEqual(calls[0]?.args, { p_checklist_item_id: ITEM_ID, p_file_id: FILE_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(item.fileId, FILE_ID);
  });

  test("classifies document_checklist_type_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "document_checklist_type_mismatch: file is a different document type" } });
    await assert.rejects(
      () => linkDocumentToChecklistItem(client, { checklistItemId: ITEM_ID, fileId: FILE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentRequirementMutationError);
        assert.equal(err.code, "document_checklist_type_mismatch");
        return true;
      },
    );
  });
});

describe("reviewDocumentChecklistItem", () => {
  test("calls review_document_checklist_item with the exact snake_case params, defaulting notes/expiresAt to null", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...ITEM_ROW, file_id: FILE_ID, review_status: "approved" }, error: null });
    const item = await reviewDocumentChecklistItem(client, { checklistItemId: ITEM_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "review_document_checklist_item");
    assert.deepEqual(calls[0]?.args, {
      p_checklist_item_id: ITEM_ID,
      p_decision: "approved",
      p_notes: null,
      p_expires_at: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(item.reviewStatus, "approved");
  });

  test("classifies document_checklist_unsafe_file for an unscanned linked file", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "document_checklist_unsafe_file: linked file has scan status pending" } });
    await assert.rejects(
      () => reviewDocumentChecklistItem(client, { checklistItemId: ITEM_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentRequirementMutationError);
        assert.equal(err.code, "document_checklist_unsafe_file");
        return true;
      },
    );
  });
});

describe("uploadShipmentDocumentFile", () => {
  const FILE_ROW = {
    id: FILE_ID,
    tenant_id: TENANT_ID,
    document_type_code: "pod",
    config_version_id: DEFINITION_ID,
    record_type: "shipment_order",
    record_id: SHIPMENT_ID,
    classification: "internal",
    original_filename: "pod-a.pdf",
    mime_type: "application/pdf",
    size_bytes: 102400,
    storage_path: `tenant/${TENANT_ID}/pod/${FILE_ID}`,
    malware_scan_status: "pending",
    malware_scan_completed_at: null,
    malware_scan_provider_ref: null,
    version_group_id: FILE_ID,
    version_number: 1,
    is_latest_version: true,
    lifecycle_status: "active",
    legal_hold: false,
    legal_hold_reason: null,
    deleted_at: null,
    uploaded_by_auth_user_id: ACTOR_ID,
    shared_org_unit_ids: [],
    customer_account_ref: null,
    idempotency_key: "idem-upload-1",
    created_at: "2026-07-28T09:00:00.000Z",
    updated_at: "2026-07-28T09:00:00.000Z",
  };

  test("calls initiate_file_upload with record_type always shipment_order", async () => {
    const { client, calls } = fakeRpcClient({ data: FILE_ROW, error: null });
    const file = await uploadShipmentDocumentFile(client, {
      tenantId: TENANT_ID,
      shipmentOrderId: SHIPMENT_ID,
      documentTypeCode: "pod",
      originalFilename: "pod-a.pdf",
      mimeType: "application/pdf",
      sizeBytes: 102400,
      idempotencyKey: "idem-upload-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "initiate_file_upload");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_document_type_code: "pod",
      p_record_type: "shipment_order",
      p_record_id: SHIPMENT_ID,
      p_original_filename: "pod-a.pdf",
      p_mime_type: "application/pdf",
      p_size_bytes: 102400,
      p_classification: null,
      p_legal_hold: false,
      p_legal_hold_reason: null,
      p_shared_org_unit_ids: [],
      p_customer_account_ref: null,
      p_idempotency_key: "idem-upload-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(file.malwareScanStatus, "pending");
  });

  test("classifies document_mime_type_not_allowed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "document_mime_type_not_allowed: application/x-msdownload is not allowed" } });
    await assert.rejects(
      () =>
        uploadShipmentDocumentFile(client, {
          tenantId: TENANT_ID,
          shipmentOrderId: SHIPMENT_ID,
          documentTypeCode: "pod",
          originalFilename: "pod-a.exe",
          mimeType: "application/x-msdownload",
          sizeBytes: 1024,
          idempotencyKey: "idem-upload-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof DocumentRequirementMutationError);
        assert.equal(err.code, "document_mime_type_not_allowed");
        return true;
      },
    );
  });
});
