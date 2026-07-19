import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerStatusSet,
  registerCanonicalStatus,
  registerStatusLegacyMapping,
  publishStatusPresentation,
  StatusMutationError,
  type StatusMutationRpcClient,
} from "./status.ts";

const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const STATUS_ID = "523e4567-e89b-12d3-a456-426614174000";
const MAPPING_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_SET_ROW = {
  code: "quotation_status",
  name: "Quotation Status",
  owner_primitive_code: "STAT",
  registered_by: "platform-core-foundation",
  created_at: "2026-07-19T00:00:00.000Z",
};

const VALID_STATUS_ROW = {
  id: STATUS_ID,
  status_set_code: "quotation_status",
  code: "draft",
  category: "initial",
  sort_order: 0,
  registered_by: "tester",
  created_at: "2026-07-19T00:00:00.000Z",
  is_terminal: false,
};

const VALID_MAPPING_ROW = {
  id: MAPPING_ID,
  status_set_code: "quotation_status",
  legacy_value: "PENDING",
  canonical_status_id: STATUS_ID,
  registered_by: "tester",
  created_at: "2026-07-19T00:00:00.000Z",
};

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: OBJECT_ID,
  version_number: 1,
  status: "published",
  effective_from: "2026-07-19T00:00:00.000Z",
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "tenant admin",
  published_by: "tenant admin",
  published_at: "2026-07-19T00:00:00.000Z",
  archived_at: null,
  archived_reason: null,
  record_version: 2,
  created_at: "2026-07-19T00:00:00.000Z",
  updated_at: "2026-07-19T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): StatusMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("registerStatusSet", () => {
  test("calls register_status_set with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_SET_ROW, error: null });
    await registerStatusSet(client, { code: "quotation_status", name: "Quotation Status", ownerPrimitiveCode: "STAT", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_code: "quotation_status",
      p_name: "Quotation Status",
      p_owner_primitive_code: "STAT",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a status set" } });
    await assert.rejects(
      () => registerStatusSet(client, { code: "x", name: "X", ownerPrimitiveCode: "STAT", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof StatusMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("registerCanonicalStatus", () => {
  test("calls register_canonical_status with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_STATUS_ROW, error: null });
    await registerCanonicalStatus(client, { statusSetCode: "quotation_status", code: "draft", category: "initial", sortOrder: 0, actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_status_set_code: "quotation_status",
      p_code: "draft",
      p_category: "initial",
      p_sort_order: 0,
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps a status_set_not_found error", async () => {
    const client = fakeClient({ data: null, error: { message: "status_set_not_found: no status set x" } });
    await assert.rejects(
      () => registerCanonicalStatus(client, { statusSetCode: "x", code: "draft", category: "initial", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof StatusMutationError);
        assert.equal(err.code, "status_set_not_found");
        return true;
      },
    );
  });
});

describe("registerStatusLegacyMapping", () => {
  test("calls register_status_legacy_mapping with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_MAPPING_ROW, error: null });
    await registerStatusLegacyMapping(client, { statusSetCode: "quotation_status", legacyValue: "PENDING", canonicalStatusCode: "draft", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_status_set_code: "quotation_status",
      p_legacy_value: "PENDING",
      p_canonical_status_code: "draft",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps a status_legacy_mapping_collision error", async () => {
    const client = fakeClient({ data: null, error: { message: "status_legacy_mapping_collision: legacy value PENDING in set x is already mapped to a different canonical status" } });
    await assert.rejects(
      () => registerStatusLegacyMapping(client, { statusSetCode: "x", legacyValue: "PENDING", canonicalStatusCode: "draft", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof StatusMutationError);
        assert.equal(err.code, "status_legacy_mapping_collision");
        return true;
      },
    );
  });
});

describe("publishStatusPresentation", () => {
  test("calls publish_status_presentation and returns the published version row", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    const version = await publishStatusPresentation(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
  });

  test("wraps a status_missing_accessible_cue error", async () => {
    const client = fakeClient({ data: null, error: { message: "status_missing_accessible_cue: entry for draft has no non-empty icon" } });
    await assert.rejects(
      () => publishStatusPresentation(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof StatusMutationError);
        assert.equal(err.code, "status_missing_accessible_cue");
        return true;
      },
    );
  });

  test("wraps a status_invalid_color error", async () => {
    const client = fakeClient({ data: null, error: { message: "status_invalid_color: entry for draft has a color that is not a #rrggbb hex value" } });
    await assert.rejects(
      () => publishStatusPresentation(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof StatusMutationError);
        assert.equal(err.code, "status_invalid_color");
        return true;
      },
    );
  });
});
