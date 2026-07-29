import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createFinanceConfigDraft,
  setFinanceConfigItems,
  publishFinanceConfigVersion,
  discardFinanceConfigDraft,
  rollbackFinanceConfigVersion,
  FinanceConfigMutationError,
  type FinanceConfigMutationRpcClient,
} from "./finance-config.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: OBJECT_ID,
  version_number: 1,
  status: "draft",
  effective_from: null,
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "finance admin",
  published_by: null,
  published_at: null,
  archived_at: null,
  archived_reason: null,
  record_version: 1,
  created_at: "2026-07-28T00:00:00.000Z",
  updated_at: "2026-07-28T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): FinanceConfigMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as FinanceConfigMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("createFinanceConfigDraft", () => {
  test("calls create_finance_config_draft with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    await createFinanceConfigDraft(client, {
      configTypeCode: "finance_rounding",
      tenantId: TENANT_ID,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: ACTOR_ID,
      createdBy: "finance admin",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_config_type_code: "finance_rounding",
      p_tenant_id: TENANT_ID,
      p_scope_level: "tenant",
      p_scope_id: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "finance admin",
    });
  });

  test("rejects a configTypeCode outside the six Finance Configuration classes before ever calling the RPC", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    const invalidInput = {
      configTypeCode: "approval",
      tenantId: TENANT_ID,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: ACTOR_ID,
      createdBy: "finance admin",
    } as unknown as Parameters<typeof createFinanceConfigDraft>[1];
    await assert.rejects(() => createFinanceConfigDraft(client, invalidInput));
    assert.equal(client.calls.length, 0);
  });

  test("wraps an insufficient_authority error (e.g. FIN:Edit missing)", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:Edit for tenant" } });
    await assert.rejects(
      () =>
        createFinanceConfigDraft(client, {
          configTypeCode: "finance_rounding",
          tenantId: TENANT_ID,
          scopeLevel: "tenant",
          scopeId: null,
          actorAuthUserId: ACTOR_ID,
          createdBy: "finance admin",
        }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceConfigMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("setFinanceConfigItems", () => {
  test("maps items to snake_case and returns the item count", async () => {
    const client = fakeClient({ data: 1, error: null });
    const count = await setFinanceConfigItems(client, {
      versionId: VERSION_ID,
      items: [{ key: "default", value: { mode: "round_half_up", precision: 2, order: "convert_then_round" } }],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "finance admin",
    });

    assert.equal(count, 1);
    assert.deepEqual(client.calls[0]?.args["p_items"], [{ key: "default", value: { mode: "round_half_up", precision: 2, order: "convert_then_round" } }]);
  });
});

describe("publishFinanceConfigVersion", () => {
  test("calls publish_finance_config_version and returns the published row", async () => {
    const publishedRow = { ...VALID_VERSION_ROW, status: "published", published_by: "finance admin" };
    const client = fakeClient({ data: publishedRow, error: null });
    const version = await publishFinanceConfigVersion(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "finance admin" });
    assert.equal(version.status, "published");
  });

  test("wraps a per-class structural validation error (e.g. finance_rounding_invalid_precision)", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_rounding_invalid_precision: rounding class default precision 9 must be between 0 and 6" } });
    await assert.rejects(
      () => publishFinanceConfigVersion(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "finance admin" }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceConfigMutationError);
        assert.equal(err.code, "finance_rounding_invalid_precision");
        return true;
      },
    );
  });
});

describe("discardFinanceConfigDraft", () => {
  test("calls discard_finance_config_draft with the exact snake_case params", async () => {
    const archivedRow = { ...VALID_VERSION_ROW, status: "archived", archived_reason: "no longer needed" };
    const client = fakeClient({ data: archivedRow, error: null });
    await discardFinanceConfigDraft(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: "no longer needed", actorLabel: "finance admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_reason: "no longer needed",
      p_actor_label: "finance admin",
    });
  });
});

describe("rollbackFinanceConfigVersion", () => {
  test("calls rollback_finance_config_version with the exact snake_case params", async () => {
    const rolledBackRow = { ...VALID_VERSION_ROW, version_number: 3, status: "published", rollback_of_version_id: VERSION_ID };
    const client = fakeClient({ data: rolledBackRow, error: null });
    const version = await rollbackFinanceConfigVersion(client, { targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: "revert bad publish", actorLabel: "finance admin" });

    assert.equal(client.calls[0]?.fn, "rollback_finance_config_version");
    assert.equal(version.rollbackOfVersionId, VERSION_ID);
  });

  test("wraps a cannot_rollback_draft error", async () => {
    const client = fakeClient({ data: null, error: { message: "cannot_rollback_draft: version is still a draft, nothing stable to roll back to" } });
    await assert.rejects(
      () => rollbackFinanceConfigVersion(client, { targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: null, actorLabel: "finance admin" }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceConfigMutationError);
        assert.equal(err.code, "cannot_rollback_draft");
        return true;
      },
    );
  });
});
