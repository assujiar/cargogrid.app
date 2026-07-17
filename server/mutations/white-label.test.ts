import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createTenantBrandDraft,
  setTenantBrandTokens,
  publishTenantBrandVersion,
  discardTenantBrandDraft,
  rollbackTenantBrandVersion,
  WhiteLabelMutationError,
  type WhiteLabelMutationRpcClient,
} from "./white-label.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_ROW = {
  id: VERSION_ID,
  tenant_id: TENANT_ID,
  version_number: 1,
  status: "draft",
  tokens: {},
  logo_asset_url: null,
  email_sender_name: null,
  email_logo_asset_url: null,
  document_template_refs: {},
  contrast_validated: false,
  contrast_report: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  effective_from: null,
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
): WhiteLabelMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("createTenantBrandDraft", () => {
  test("calls create_tenant_brand_draft with the exact snake_case params the SQL function expects", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await createTenantBrandDraft(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, createdBy: "tenant admin" });

    assert.equal(client.calls[0]?.fn, "create_tenant_brand_draft");
    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "tenant admin",
    });
  });

  test("wraps an insufficient_authority error into a typed WhiteLabelMutationError", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x holds neither Supreme Admin nor tenant_admin authority" } });
    await assert.rejects(
      () => createTenantBrandDraft(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof WhiteLabelMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("setTenantBrandTokens", () => {
  test("calls set_tenant_brand_tokens with defaults applied for omitted optional fields", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await setTenantBrandTokens(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_tokens: {},
      p_logo_asset_url: null,
      p_email_sender_name: null,
      p_email_logo_asset_url: null,
      p_document_template_refs: {},
      p_actor_label: "tenant admin",
    });
  });

  test("rejects invalid input (malformed hex color) before ever calling the RPC", async () => {
    const client = fakeClient({ data: VALID_ROW, error: null });
    await assert.rejects(() =>
      setTenantBrandTokens(client, {
        versionId: VERSION_ID,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
        tokens: { primary: "not-a-color" } as never,
      }),
    );
    assert.equal(client.calls.length, 0);
  });

  test("wraps a brand_version_not_draft error (e.g. attempting to edit a published version)", async () => {
    const client = fakeClient({ data: null, error: { message: "brand_version_not_draft: version x is published, only a draft's tokens may be changed" } });
    await assert.rejects(
      () => setTenantBrandTokens(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof WhiteLabelMutationError);
        assert.equal(err.code, "brand_version_not_draft");
        return true;
      },
    );
  });
});

describe("publishTenantBrandVersion", () => {
  test("calls publish_tenant_brand_version with the exact snake_case params", async () => {
    const publishedRow = { ...VALID_ROW, status: "published", published_by: "tenant admin", contrast_validated: true };
    const client = fakeClient({ data: publishedRow, error: null });
    const version = await publishTenantBrandVersion(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });

    assert.equal(client.calls[0]?.fn, "publish_tenant_brand_version");
    assert.equal(version.status, "published");
  });

  test("wraps an insufficient_contrast error (the enforced accessibility gate)", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_contrast: primary color contrast ratio 1.2 is below the 4.5:1 WCAG AA minimum" } });
    await assert.rejects(
      () => publishTenantBrandVersion(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof WhiteLabelMutationError);
        assert.equal(err.code, "insufficient_contrast");
        return true;
      },
    );
  });
});

describe("discardTenantBrandDraft", () => {
  test("calls discard_tenant_brand_draft with the exact snake_case params", async () => {
    const archivedRow = { ...VALID_ROW, status: "archived", archived_reason: "no longer needed" };
    const client = fakeClient({ data: archivedRow, error: null });
    await discardTenantBrandDraft(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: "no longer needed", actorLabel: "tenant admin" });

    assert.deepEqual(client.calls[0]?.args, {
      p_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_reason: "no longer needed",
      p_actor_label: "tenant admin",
    });
  });
});

describe("rollbackTenantBrandVersion", () => {
  test("calls rollback_tenant_brand_version with the exact snake_case params", async () => {
    const rolledBackRow = { ...VALID_ROW, version_number: 3, status: "published", rollback_of_version_id: VERSION_ID };
    const client = fakeClient({ data: rolledBackRow, error: null });
    const version = await rollbackTenantBrandVersion(client, { targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: "revert bad publish", actorLabel: "tenant admin" });

    assert.equal(client.calls[0]?.fn, "rollback_tenant_brand_version");
    assert.deepEqual(client.calls[0]?.args, {
      p_target_version_id: VERSION_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_reason: "revert bad publish",
      p_actor_label: "tenant admin",
    });
    assert.equal(version.rollbackOfVersionId, VERSION_ID);
  });

  test("wraps a cannot_rollback_draft error", async () => {
    const client = fakeClient({ data: null, error: { message: "cannot_rollback_draft: version x is still a draft, nothing stable to roll back to" } });
    await assert.rejects(
      () => rollbackTenantBrandVersion(client, { targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, reason: null, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof WhiteLabelMutationError);
        assert.equal(err.code, "cannot_rollback_draft");
        return true;
      },
    );
  });
});
