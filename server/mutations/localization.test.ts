import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createTenantLocaleDraft,
  setTenantLocaleConfig,
  publishTenantLocaleVersion,
  discardTenantLocaleDraft,
  rollbackTenantLocaleVersion,
  LocalizationMutationError,
  type LocalizationMutationRpcClient,
} from "./localization.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_ROW = {
  id: VERSION_ID,
  tenant_id: TENANT_ID,
  version_number: 1,
  status: "draft",
  default_locale: "id",
  default_timezone: "Asia/Jakarta",
  default_currency: "IDR",
  terminology_overrides: {},
  effective_from: null,
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
): LocalizationMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("createTenantLocaleDraft", () => {
  test("calls create_tenant_locale_draft with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await createTenantLocaleDraft(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, createdBy: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tenant admin",
    });
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity holds neither Supreme Admin nor tenant_admin authority" } });
    await assert.rejects(
      () => createTenantLocaleDraft(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof LocalizationMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("setTenantLocaleConfig", () => {
  test("calls set_tenant_locale_config with defaults applied", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await setTenantLocaleConfig(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_default_locale: "id",
      p_default_timezone: "Asia/Jakarta",
      p_default_currency: "IDR",
      p_terminology_overrides: {},
      p_actor_label: "tenant admin",
    });
  });

  test("rejects an unsupported locale before ever calling the RPC", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await assert.rejects(() =>
      setTenantLocaleConfig(client, {
        versionId: VERSION_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
        defaultLocale: "fr" as never,
      }),
    );
    assert.equal(client.calls.length, 0);
  });

  test("wraps an invalid_terminology_overrides error", async () => {
    const client = fakeClient({ data: null, error: { message: "invalid_terminology_overrides: terminology_overrides contains an unknown canonical_terms code" } });
    await assert.rejects(
      () => setTenantLocaleConfig(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof LocalizationMutationError);
        assert.equal(err.code, "invalid_terminology_overrides");
        return true;
      },
    );
  });
});

describe("publishTenantLocaleVersion", () => {
  test("calls publish_tenant_locale_version and returns the published row", async () => {
    const publishedRow = { ...VALID_ROW, status: "published", published_by: "tenant admin" };
    const client = fakeClient({ data: publishedRow, error: null });
    const version = await publishTenantLocaleVersion(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
  });
});

describe("discardTenantLocaleDraft", () => {
  test("calls discard_tenant_locale_draft with the exact snake_case params", async () => {
    const archivedRow = { ...VALID_ROW, status: "archived", archived_reason: "no longer needed" };
    const client = fakeClient({ data: archivedRow, error: null });
    await discardTenantLocaleDraft(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: "no longer needed", actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_reason: "no longer needed",
      p_actor_label: "tenant admin",
    });
  });
});

describe("rollbackTenantLocaleVersion", () => {
  test("calls rollback_tenant_locale_version with the exact snake_case params", async () => {
    const rolledBackRow = { ...VALID_ROW, version_number: 3, status: "published", rollback_of_version_id: VERSION_ID };
    const client = fakeClient({ data: rolledBackRow, error: null });
    const version = await rollbackTenantLocaleVersion(client, { targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: "revert bad publish", actorLabel: "tenant admin" });

    assert.equal(client.calls[0]?.fn, "rollback_tenant_locale_version");
    assert.equal(version.rollbackOfVersionId, VERSION_ID);
  });

  test("wraps a cannot_rollback_draft error", async () => {
    const client = fakeClient({ data: null, error: { message: "cannot_rollback_draft: version is still a draft, nothing stable to roll back to" } });
    await assert.rejects(
      () => rollbackTenantLocaleVersion(client, { targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: null, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof LocalizationMutationError);
        assert.equal(err.code, "cannot_rollback_draft");
        return true;
      },
    );
  });
});
