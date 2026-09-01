import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  uploadLoyaltyRewardMediaFile,
  publishLoyaltyRewardTermsDocumentTypeDefinition,
  LoyaltyRewardMediaMutationError,
  LOYALTY_REWARD_TERMS_ALLOWED_MIME_TYPES,
  type LoyaltyRewardMediaMutationRpcClient,
  type PublishLoyaltyRewardTermsDocumentTypeRpcClient,
} from "./loyalty-reward-media.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "323e4567-e89b-12d3-a456-426614174000";
const FILE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "623e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "723e4567-e89b-12d3-a456-426614174000";

const FILE_ROW = {
  id: FILE_ID,
  tenant_id: TENANT_ID,
  document_type_code: "reward_terms",
  config_version_id: VERSION_ID,
  record_type: "loyalty_reward",
  record_id: RECORD_ID,
  classification: "internal",
  original_filename: "terms.pdf",
  mime_type: "application/pdf",
  size_bytes: 20480,
  storage_path: "tenant/x/reward_terms/y",
  malware_scan_status: "pending",
  malware_scan_completed_at: null,
  malware_scan_provider_ref: null,
  version_group_id: "823e4567-e89b-12d3-a456-426614174000",
  version_number: 1,
  is_latest_version: true,
  lifecycle_status: "active",
  legal_hold: false,
  legal_hold_reason: null,
  deleted_at: null,
  uploaded_by_auth_user_id: ACTOR_ID,
  shared_org_unit_ids: [],
  customer_account_ref: null,
  idempotency_key: "reward-file-1",
  created_at: "2026-09-01T00:00:00.000Z",
  updated_at: "2026-09-01T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyRewardMediaMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyRewardMediaMutationRpcClient;
  return { client, calls };
}

describe("uploadLoyaltyRewardMediaFile", () => {
  test("fixes documentTypeCode/recordType to this capability's own constants, forwards everything else", async () => {
    const { client, calls } = fakeRpcClient({ data: FILE_ROW, error: null });
    const result = await uploadLoyaltyRewardMediaFile(client, {
      tenantId: TENANT_ID,
      recordId: RECORD_ID,
      originalFilename: "terms.pdf",
      mimeType: "application/pdf",
      sizeBytes: 20480,
      idempotencyKey: "reward-file-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.recordId, RECORD_ID);
    assert.deepEqual(calls[0], {
      fn: "initiate_file_upload",
      args: {
        p_tenant_id: TENANT_ID,
        p_document_type_code: "reward_terms",
        p_record_type: "loyalty_reward",
        p_record_id: RECORD_ID,
        p_original_filename: "terms.pdf",
        p_mime_type: "application/pdf",
        p_size_bytes: 20480,
        p_classification: null,
        p_legal_hold: false,
        p_legal_hold_reason: null,
        p_shared_org_unit_ids: [],
        p_customer_account_ref: null,
        p_idempotency_key: "reward-file-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  for (const code of [
    "file_actor_unauthorized",
    "document_type_not_configured",
    "document_unsafe_filename",
    "document_mime_type_not_allowed",
    "document_file_too_large",
    "document_invalid_classification",
    "document_classification_too_weak",
  ] as const) {
    test(`classifies ${code}`, async () => {
      const { client } = fakeRpcClient({ data: null, error: { message: `${code}: synthetic message for this error class` } });
      await assert.rejects(
        () =>
          uploadLoyaltyRewardMediaFile(client, {
            tenantId: TENANT_ID,
            recordId: RECORD_ID,
            originalFilename: "terms.pdf",
            mimeType: "application/pdf",
            sizeBytes: 20480,
            actorAuthUserId: ACTOR_ID,
            actorLabel: "x",
          }),
        (err: unknown) => {
          assert.ok(err instanceof LoyaltyRewardMediaMutationError);
          assert.equal(err.code, code);
          return true;
        },
      );
    });
  }

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "something_else: unrelated failure" } });
    await assert.rejects(
      () =>
        uploadLoyaltyRewardMediaFile(client, {
          tenantId: TENANT_ID,
          recordId: RECORD_ID,
          originalFilename: "terms.pdf",
          mimeType: "application/pdf",
          sizeBytes: 20480,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "x",
        }),
      (err: unknown) => {
        assert.ok(err instanceof LoyaltyRewardMediaMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("publishLoyaltyRewardTermsDocumentTypeDefinition", () => {
  test("calls create_config_draft -> set_config_items -> publish_document_type_definition, in order, with the right keys", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const draftRow = {
      id: VERSION_ID,
      config_object_id: OBJECT_ID,
      version_number: 1,
      status: "draft",
      effective_from: null,
      effective_to: null,
      cloned_from_version_id: null,
      rollback_of_version_id: null,
      created_by: "tenant admin",
      published_by: null,
      published_at: null,
      archived_at: null,
      archived_reason: null,
      record_version: 1,
      created_at: "2026-09-01T00:00:00.000Z",
      updated_at: "2026-09-01T00:00:00.000Z",
    };
    const publishedRow = { ...draftRow, status: "published", published_by: "tenant admin", published_at: "2026-09-01T00:00:01.000Z", record_version: 2 };

    const responses: Record<string, { data: unknown; error: { message: string } | null }> = {
      create_config_draft: { data: draftRow, error: null },
      set_config_items: { data: 5, error: null },
      publish_document_type_definition: { data: publishedRow, error: null },
    };

    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return responses[fn];
      },
    } as unknown as PublishLoyaltyRewardTermsDocumentTypeRpcClient;

    const result = await publishLoyaltyRewardTermsDocumentTypeDefinition(client, {
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "docadmin1",
    });

    assert.equal(result.status, "published");
    assert.deepEqual(
      calls.map((c) => c.fn),
      ["create_config_draft", "set_config_items", "publish_document_type_definition"],
    );

    const [createCall, setItemsCall, publishCall] = calls;
    assert.ok(createCall && setItemsCall && publishCall);

    assert.deepEqual(createCall.args, {
      p_config_type_code: "document:reward_terms",
      p_tenant_id: TENANT_ID,
      p_scope_level: "tenant",
      p_scope_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "docadmin1",
    });

    assert.equal(setItemsCall.args.p_version_id, VERSION_ID);
    const items = setItemsCall.args.p_items as { key: string; value: unknown; canonical_ref: string | null }[];
    const byKey = Object.fromEntries(items.map((item) => [item.key, item.value]));
    assert.deepEqual(byKey.allowed_mime_types, [...LOYALTY_REWARD_TERMS_ALLOWED_MIME_TYPES]);
    assert.equal(byKey.max_size_bytes, 10_485_760);
    assert.equal(byKey.retention_class, "none");
    assert.equal(byKey.default_classification, "internal");
    assert.equal(byKey.legal_hold_eligible, false);

    assert.deepEqual(publishCall.args, {
      p_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_effective_from: null,
      p_actor_label: "docadmin1",
    });
  });

  test("wraps a config/document-layer failure into LoyaltyRewardMediaMutationError", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "config_version_not_found: no such version" } };
      },
    } as unknown as PublishLoyaltyRewardTermsDocumentTypeRpcClient;

    await assert.rejects(
      () => publishLoyaltyRewardTermsDocumentTypeDefinition(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "docadmin1" }),
      (err: unknown) => {
        assert.ok(err instanceof LoyaltyRewardMediaMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
