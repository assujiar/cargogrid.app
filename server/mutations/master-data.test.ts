import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerMasterType,
  createMasterRecord,
  updateMasterRecord,
  deactivateMasterRecord,
  mergeMasterRecords,
  MasterDataMutationError,
  type MasterDataMutationRpcClient,
} from "./master-data.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "323e4567-e89b-12d3-a456-426614174000";
const TARGET_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_TYPE_ROW = {
  code: "vendor_rate",
  name: "Vendor Rate",
  scope: "tenant",
  owner_module_code: "PRC",
  registered_by: "platform-core-foundation",
  created_at: "2026-07-17T00:00:00.000Z",
};

const VALID_RECORD_ROW = {
  id: RECORD_ID,
  master_type_code: "vendor_rate",
  tenant_id: TENANT_ID,
  code: "VR-001",
  name: "Sample Vendor Rate",
  aliases: [],
  attributes: {},
  canonical_status: "active",
  merged_into_id: null,
  effective_from: "2026-07-17T00:00:00.000Z",
  effective_to: null,
  created_by: "tenant admin",
  deactivated_at: null,
  deactivated_by: null,
  deactivated_reason: null,
  merged_at: null,
  merged_by: null,
  record_version: 1,
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): MasterDataMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("registerMasterType", () => {
  test("calls register_master_type with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_TYPE_ROW, error: null });
    await registerMasterType(client, { code: "vendor_rate", name: "Vendor Rate", scope: "tenant", ownerModuleCode: "PRC", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_code: "vendor_rate",
      p_name: "Vendor Rate",
      p_scope: "tenant",
      p_owner_module_code: "PRC",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps an insufficient_authority error (not Supreme Admin)", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a master type" } });
    await assert.rejects(
      () => registerMasterType(client, { code: "x", name: "X", scope: "global", ownerModuleCode: null, actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof MasterDataMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("createMasterRecord", () => {
  test("calls create_master_record with defaults applied for omitted aliases/attributes", async () => {
    const client = fakeClient({ data: VALID_RECORD_ROW, error: null });
    await createMasterRecord(client, { masterTypeCode: "vendor_rate", tenantId: TENANT_ID, code: "VR-001", name: "Sample Vendor Rate", actorAuthUserId: ACTOR_ID, createdBy: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_master_type_code: "vendor_rate",
      p_tenant_id: TENANT_ID,
      p_code: "VR-001",
      p_name: "Sample Vendor Rate",
      p_aliases: [],
      p_attributes: {},
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tenant admin",
    });
  });

  test("wraps a master_record_already_exists error", async () => {
    const client = fakeClient({ data: null, error: { message: "master_record_already_exists: code VR-001 already exists for master type vendor_rate" } });
    await assert.rejects(
      () => createMasterRecord(client, { masterTypeCode: "vendor_rate", tenantId: TENANT_ID, code: "VR-001", name: "x", actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof MasterDataMutationError);
        assert.equal(err.code, "master_record_already_exists");
        return true;
      },
    );
  });

  test("rejects an attribute value containing an angle bracket before ever calling the RPC", async () => {
    const client = fakeClient({ data: VALID_RECORD_ROW, error: null });
    await assert.rejects(() =>
      createMasterRecord(client, {
        masterTypeCode: "vendor_rate",
        tenantId: TENANT_ID,
        code: "VR-002",
        name: "x",
        attributes: { note: "<script>alert(1)</script>" },
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
    assert.equal(client.calls.length, 0);
  });
});

describe("updateMasterRecord", () => {
  test("calls update_master_record with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...VALID_RECORD_ROW, name: "Updated Name", record_version: 2 }, error: null });
    const record = await updateMasterRecord(client, { recordId: RECORD_ID, expectedVersion: 1, name: "Updated Name", actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });

    assert.equal(client.calls[0]?.fn, "update_master_record");
    assert.equal(record.name, "Updated Name");
  });

  test("wraps a stale_record_version error", async () => {
    const client = fakeClient({ data: null, error: { message: "stale_record_version: expected version 1 but record is at version 2" } });
    await assert.rejects(
      () => updateMasterRecord(client, { recordId: RECORD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof MasterDataMutationError);
        assert.equal(err.code, "stale_record_version");
        return true;
      },
    );
  });
});

describe("deactivateMasterRecord", () => {
  test("calls deactivate_master_record with the exact snake_case params", async () => {
    const deactivatedRow = { ...VALID_RECORD_ROW, canonical_status: "deactivated", deactivated_reason: "no longer used" };
    const client = fakeClient({ data: deactivatedRow, error: null });
    await deactivateMasterRecord(client, { recordId: RECORD_ID, actorAuthUserId: ACTOR_ID, reason: "no longer used", actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_record_id: RECORD_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_reason: "no longer used",
      p_actor_label: "tenant admin",
    });
  });
});

describe("mergeMasterRecords", () => {
  test("calls merge_master_records with the exact snake_case params", async () => {
    const targetRow = { ...VALID_RECORD_ROW, id: TARGET_ID, aliases: ["VR-001"] };
    const client = fakeClient({ data: targetRow, error: null });
    const record = await mergeMasterRecords(client, { sourceId: RECORD_ID, targetId: TARGET_ID, actorAuthUserId: ACTOR_ID, reason: "duplicate entry", actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_source_id: RECORD_ID,
      p_target_id: TARGET_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_reason: "duplicate entry",
      p_actor_label: "tenant admin",
    });
    assert.equal(record.id, TARGET_ID);
  });

  test("wraps an invalid_merge error", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_merge: cannot merge a master record into itself" } });
    await assert.rejects(
      () => mergeMasterRecords(client, { sourceId: RECORD_ID, targetId: RECORD_ID, actorAuthUserId: ACTOR_ID, reason: "x", actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof MasterDataMutationError);
        assert.equal(err.code, "invalid_merge");
        return true;
      },
    );
  });
});
