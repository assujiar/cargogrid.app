import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  RegisterFeatureFlagInputSchema,
  SetFeatureFlagItemsInputSchema,
  EvaluateFeatureFlagInputSchema,
  parseFeatureFlag,
  parseFeatureFlagDecision,
} from "./feature-flag.ts";

describe("RegisterFeatureFlagInputSchema", () => {
  test("accepts a well-formed flag_key", () => {
    const parsed = RegisterFeatureFlagInputSchema.parse({
      flagKey: "platform.example_rollout",
      name: "Example",
      actorAuthUserId: "123e4567-e89b-12d3-a456-426614174000",
      registeredBy: "supreme admin",
    });
    assert.equal(parsed.flagKey, "platform.example_rollout");
    assert.equal(parsed.moduleCode, null, "moduleCode defaults to null");
  });

  test("rejects an uppercase or malformed flag_key", () => {
    assert.throws(() =>
      RegisterFeatureFlagInputSchema.parse({
        flagKey: "Platform.BadKey",
        name: "Example",
        actorAuthUserId: "123e4567-e89b-12d3-a456-426614174000",
        registeredBy: "supreme admin",
      }),
    );
  });
});

describe("SetFeatureFlagItemsInputSchema", () => {
  test("rejects a rollout_percentage outside [0, 100]", () => {
    assert.throws(() =>
      SetFeatureFlagItemsInputSchema.parse({
        versionId: "123e4567-e89b-12d3-a456-426614174000",
        actorAuthUserId: "123e4567-e89b-12d3-a456-426614174000",
        actorLabel: "supreme admin",
        rolloutPercentage: 150,
      }),
    );
  });

  test("rejects an environment outside the known enum", () => {
    assert.throws(() =>
      SetFeatureFlagItemsInputSchema.parse({
        versionId: "123e4567-e89b-12d3-a456-426614174000",
        actorAuthUserId: "123e4567-e89b-12d3-a456-426614174000",
        actorLabel: "supreme admin",
        environments: ["moon_base"],
      }),
    );
  });

  test("accepts an all-defaults input (only version/actor/label required)", () => {
    const parsed = SetFeatureFlagItemsInputSchema.parse({
      versionId: "123e4567-e89b-12d3-a456-426614174000",
      actorAuthUserId: "123e4567-e89b-12d3-a456-426614174000",
      actorLabel: "supreme admin",
    });
    assert.equal(parsed.killSwitch, null);
    assert.equal(parsed.rolloutPercentage, null);
  });
});

describe("EvaluateFeatureFlagInputSchema", () => {
  test("defaults cohorts to an empty array", () => {
    const parsed = EvaluateFeatureFlagInputSchema.parse({
      flagKey: "platform.example_rollout",
      tenantId: "123e4567-e89b-12d3-a456-426614174000",
      environment: "production",
    });
    assert.deepEqual(parsed.cohorts, []);
  });

  test("accepts a null tenantId (platform-wide evaluation)", () => {
    const parsed = EvaluateFeatureFlagInputSchema.parse({
      flagKey: "platform.example_rollout",
      tenantId: null,
      environment: "production",
    });
    assert.equal(parsed.tenantId, null);
  });
});

describe("parseFeatureFlag", () => {
  test("maps a raw snake_case row to camelCase", () => {
    const flag = parseFeatureFlag({
      flag_key: "platform.example_rollout",
      name: "Example Rollout",
      description: null,
      module_code: "COM",
      registered_by: "supreme admin",
      created_at: "2026-07-21T00:00:00.000Z",
    });
    assert.equal(flag.flagKey, "platform.example_rollout");
    assert.equal(flag.moduleCode, "COM");
  });
});

describe("parseFeatureFlagDecision", () => {
  test("maps a raw snake_case row to camelCase", () => {
    const decision = parseFeatureFlagDecision({
      enabled: true,
      reason: "rollout_bucket",
      resolved_scope_level: "global",
      resolved_version_id: "123e4567-e89b-12d3-a456-426614174000",
      evaluated_at: "2026-07-21T00:00:00.000Z",
    });
    assert.equal(decision.enabled, true);
    assert.equal(decision.resolvedScopeLevel, "global");
  });

  test("rejects an unknown reason value (drift guard against the migration's own enum)", () => {
    assert.throws(() =>
      parseFeatureFlagDecision({
        enabled: false,
        reason: "made_up_reason",
        resolved_scope_level: null,
        resolved_version_id: null,
        evaluated_at: "2026-07-21T00:00:00.000Z",
      }),
    );
  });
});
