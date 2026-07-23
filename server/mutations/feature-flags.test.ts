import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerFeatureFlag,
  createFeatureFlagDraft,
  setFeatureFlagItems,
  killFeatureFlag,
  debugFeatureFlag,
  FeatureFlagMutationError,
  type FeatureFlagMutationRpcClient,
} from "./feature-flags.ts";
import { FeatureFlagCache } from "../queries/feature-flags.ts";

const ACTOR_ID = "123e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "223e4567-e89b-12d3-a456-426614174000";

const FLAG_ROW = {
  flag_key: "platform.example_rollout",
  name: "Example Rollout",
  description: null,
  module_code: null,
  registered_by: "supreme admin",
  created_at: "2026-07-21T00:00:00.000Z",
};

const VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: "323e4567-e89b-12d3-a456-426614174000",
  version_number: 1,
  status: "draft",
  effective_from: null,
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "supreme admin",
  published_by: null,
  published_at: null,
  archived_at: null,
  archived_reason: null,
  record_version: 1,
  created_at: "2026-07-21T00:00:00.000Z",
  updated_at: "2026-07-21T00:00:00.000Z",
};

const DECISION_ROW = {
  enabled: true,
  reason: "rollout_bucket",
  resolved_scope_level: "global",
  resolved_version_id: VERSION_ID,
  evaluated_at: "2026-07-21T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): FeatureFlagMutationRpcClient {
  return { async rpc() { return response; } };
}

describe("registerFeatureFlag", () => {
  test("returns a typed flag on success", async () => {
    const flag = await registerFeatureFlag(fakeClient({ data: FLAG_ROW, error: null }), {
      flagKey: "platform.example_rollout",
      name: "Example Rollout",
      actorAuthUserId: ACTOR_ID,
      registeredBy: "supreme admin",
    });
    assert.equal(flag.flagKey, "platform.example_rollout");
  });

  test("classifies insufficient_authority errors", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a feature flag" } });
    await assert.rejects(
      () => registerFeatureFlag(client, { flagKey: "platform.example_rollout", name: "x", actorAuthUserId: ACTOR_ID, registeredBy: "tenant admin" }),
      (err: unknown) => err instanceof FeatureFlagMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("createFeatureFlagDraft", () => {
  test("returns a typed version on success", async () => {
    const version = await createFeatureFlagDraft(fakeClient({ data: VERSION_ROW, error: null }), {
      flagKey: "platform.example_rollout",
      tenantId: null,
      scopeLevel: "global",
      actorAuthUserId: ACTOR_ID,
      createdBy: "supreme admin",
    });
    assert.equal(version.status, "draft");
  });

  test("classifies feature_flag_not_found errors", async () => {
    const client = fakeClient({ data: null, error: { message: "feature_flag_not_found: no feature flag platform.nope" } });
    await assert.rejects(
      () => createFeatureFlagDraft(client, { flagKey: "platform.nope", tenantId: null, scopeLevel: "global", actorAuthUserId: ACTOR_ID, createdBy: "x" }),
      (err: unknown) => err instanceof FeatureFlagMutationError && err.code === "feature_flag_not_found",
    );
  });
});

describe("setFeatureFlagItems", () => {
  test("returns the item count and invalidates the given cache", async () => {
    let capturedArgs: Record<string, unknown> | undefined;
    const client: FeatureFlagMutationRpcClient = {
      async rpc(_fn, args) {
        capturedArgs = args;
        return { data: 4, error: null };
      },
    };
    const cache = new FeatureFlagCache(60_000);
    let invalidated = false;
    cache.invalidate = () => {
      invalidated = true;
    };

    const count = await setFeatureFlagItems(
      client,
      { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "supreme admin", killSwitch: false, environments: ["production"], rolloutPercentage: 50, cohorts: [] },
      cache,
    );

    assert.equal(count, 4);
    assert.equal(capturedArgs?.p_rollout_percentage, 50);
    assert.equal(invalidated, true, "a successful set must invalidate the evaluation cache (prompt invalidation)");
  });

  test("classifies feature_flag_tenant_scope_no_kill_switch errors", async () => {
    const client = fakeClient({ data: null, error: { message: "feature_flag_tenant_scope_no_kill_switch: kill_switch/environments are global-only, non-overridable dimensions" } });
    await assert.rejects(
      () => setFeatureFlagItems(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "x", killSwitch: true }),
      (err: unknown) => err instanceof FeatureFlagMutationError && err.code === "feature_flag_tenant_scope_no_kill_switch",
    );
  });
});

describe("killFeatureFlag", () => {
  test("returns the published version and invalidates the given cache", async () => {
    const client = fakeClient({ data: { ...VERSION_ROW, status: "published" }, error: null });
    const cache = new FeatureFlagCache(60_000);
    let invalidated = false;
    cache.invalidate = () => {
      invalidated = true;
    };

    const version = await killFeatureFlag(client, { flagKey: "platform.example_rollout", actorAuthUserId: ACTOR_ID, reason: "incident", actorLabel: "supreme admin" }, cache);

    assert.equal(version.status, "published");
    assert.equal(invalidated, true);
  });
});

describe("debugFeatureFlag", () => {
  test("returns a typed decision and is never cached by this layer", async () => {
    const decision = await debugFeatureFlag(fakeClient({ data: DECISION_ROW, error: null }), {
      flagKey: "platform.example_rollout",
      tenantId: null,
      environment: "production",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supreme admin",
    });
    assert.equal(decision.reason, "rollout_bucket");
  });

  test("classifies insufficient_authority errors", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may debug a platform-wide feature flag evaluation" } });
    await assert.rejects(
      () => debugFeatureFlag(client, { flagKey: "platform.example_rollout", tenantId: null, environment: "production", actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => err instanceof FeatureFlagMutationError && err.code === "insufficient_authority",
    );
  });
});
