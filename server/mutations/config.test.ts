import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerConfigType,
  createConfigDraft,
  setConfigItems,
  publishConfigVersion,
  discardConfigDraft,
  rollbackConfigVersion,
  ConfigMutationError,
  type ConfigMutationRpcClient,
} from "./config.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_TYPE_ROW = {
  code: "approval",
  name: "Approval",
  owner_primitive_code: "APPR",
  registered_by: "platform-core-foundation",
  created_at: "2026-07-17T00:00:00.000Z",
};

const VALID_VERSION_ROW = {
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
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): ConfigMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("registerConfigType", () => {
  test("calls register_config_type with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_TYPE_ROW, error: null });
    await registerConfigType(client, { code: "approval", name: "Approval", ownerPrimitiveCode: "APPR", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_code: "approval",
      p_name: "Approval",
      p_owner_primitive_code: "APPR",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a config type" } });
    await assert.rejects(
      () => registerConfigType(client, { code: "x", name: "X", ownerPrimitiveCode: "X", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ConfigMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("createConfigDraft", () => {
  test("calls create_config_draft with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    await createConfigDraft(client, { configTypeCode: "approval", tenantId: TENANT_ID, scopeLevel: "tenant", scopeId: null, actorAuthUserId: ACTOR_ID, createdBy: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_config_type_code: "approval",
      p_tenant_id: TENANT_ID,
      p_scope_level: "tenant",
      p_scope_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tenant admin",
    });
  });
});

describe("setConfigItems", () => {
  test("maps items to snake_case and returns the item count", async () => {
    const client = fakeClient({ data: 2, error: null });
    const count = await setConfigItems(client, {
      versionId: VERSION_ID,
      items: [
        { key: "threshold", value: 1000 },
        { key: "approver", value: "manager", canonicalRef: null },
      ],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant admin",
    });

    assert.equal(count, 2);
    assert.deepEqual(client.calls[0]?.args["p_items"], [
      { key: "threshold", value: 1000, canonical_ref: null },
      { key: "approver", value: "manager", canonical_ref: null },
    ]);
  });

  test("rejects an unsafe item value before ever calling the RPC", async () => {
    const client = fakeClient({ data: 1, error: null });
    await assert.rejects(() =>
      setConfigItems(client, {
        versionId: VERSION_ID,
        items: [{ key: "note", value: "<script>alert(1)</script>" }],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
      }),
    );
    assert.equal(client.calls.length, 0);
  });
});

describe("publishConfigVersion", () => {
  test("calls publish_config_version and returns the published row", async () => {
    const publishedRow = { ...VALID_VERSION_ROW, status: "published", published_by: "tenant admin" };
    const client = fakeClient({ data: publishedRow, error: null });
    const version = await publishConfigVersion(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
  });

  test("wraps a circular_config_dependency error", async () => {
    const client = fakeClient({ data: null, error: { message: "circular_config_dependency: a dependency cycle was detected starting from config_item x" } });
    await assert.rejects(
      () => publishConfigVersion(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ConfigMutationError);
        assert.equal(err.code, "circular_config_dependency");
        return true;
      },
    );
  });
});

describe("discardConfigDraft", () => {
  test("calls discard_config_draft with the exact snake_case params", async () => {
    const archivedRow = { ...VALID_VERSION_ROW, status: "archived", archived_reason: "no longer needed" };
    const client = fakeClient({ data: archivedRow, error: null });
    await discardConfigDraft(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: "no longer needed", actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_reason: "no longer needed",
      p_actor_label: "tenant admin",
    });
  });
});

describe("rollbackConfigVersion", () => {
  test("calls rollback_config_version with the exact snake_case params", async () => {
    const rolledBackRow = { ...VALID_VERSION_ROW, version_number: 3, status: "published", rollback_of_version_id: VERSION_ID };
    const client = fakeClient({ data: rolledBackRow, error: null });
    const version = await rollbackConfigVersion(client, { targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: "revert bad publish", actorLabel: "tenant admin" });

    assert.equal(client.calls[0]?.fn, "rollback_config_version");
    assert.equal(version.rollbackOfVersionId, VERSION_ID);
  });

  test("wraps a cannot_rollback_draft error", async () => {
    const client = fakeClient({ data: null, error: { message: "cannot_rollback_draft: version is still a draft, nothing stable to roll back to" } });
    await assert.rejects(
      () => rollbackConfigVersion(client, { targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: null, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof ConfigMutationError);
        assert.equal(err.code, "cannot_rollback_draft");
        return true;
      },
    );
  });
});
