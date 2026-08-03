import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { upsertTenantTrackingSourcePolicy, TrackingSourcePolicyMutationError, type TrackingSourcePolicyMutationRpcClient } from "./tracking-source-policy.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: TrackingSourcePolicyMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TrackingSourcePolicyMutationRpcClient;
  return { client, calls };
}

const POLICY_ROW = {
  id: "323e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  default_source_priority: ["direct_device", "driver_mobile"],
  freshness_threshold_seconds: 180,
  accuracy_threshold_meters: 50,
  switch_hysteresis_seconds: 90,
  record_version: 1,
  created_by: "tenant admin",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("upsertTenantTrackingSourcePolicy", () => {
  test("calls upsert_tenant_tracking_source_policy with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: POLICY_ROW, error: null });
    const policy = await upsertTenantTrackingSourcePolicy(client, {
      tenantId: TENANT_ID,
      defaultSourcePriority: ["direct_device", "driver_mobile"],
      freshnessThresholdSeconds: 180,
      accuracyThresholdMeters: 50,
      switchHysteresisSeconds: 90,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant admin",
    });
    assert.deepEqual(policy.defaultSourcePriority, ["direct_device", "driver_mobile"]);
    assert.equal(calls[0]?.fn, "upsert_tenant_tracking_source_policy");
    assert.deepEqual(calls[0]?.args.p_default_source_priority, ["direct_device", "driver_mobile"]);
    assert.equal(calls[0]?.args.p_freshness_threshold_seconds, 180);
  });

  test("classifies an insufficient_authority error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:Edit" } });
    await assert.rejects(
      () =>
        upsertTenantTrackingSourcePolicy(client, {
          tenantId: TENANT_ID,
          defaultSourcePriority: ["driver_mobile"],
          freshnessThresholdSeconds: 180,
          accuracyThresholdMeters: 50,
          switchHysteresisSeconds: 90,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "viewer",
        }),
      (error: unknown) => error instanceof TrackingSourcePolicyMutationError && error.code === "insufficient_authority",
    );
  });

  test("classifies an invalid_source_priority error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_source_priority: default_source_priority must not be empty" } });
    await assert.rejects(
      () =>
        upsertTenantTrackingSourcePolicy(client, {
          tenantId: TENANT_ID,
          defaultSourcePriority: ["driver_mobile"],
          freshnessThresholdSeconds: 180,
          accuracyThresholdMeters: 50,
          switchHysteresisSeconds: 90,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tenant admin",
        }),
      (error: unknown) => error instanceof TrackingSourcePolicyMutationError && error.code === "invalid_source_priority",
    );
  });

  test("rejects an empty defaultSourcePriority before ever calling rpc (zod schema minimum)", async () => {
    const { client, calls } = fakeRpcClient({ data: POLICY_ROW, error: null });
    await assert.rejects(() =>
      upsertTenantTrackingSourcePolicy(client, {
        tenantId: TENANT_ID,
        defaultSourcePriority: [],
        freshnessThresholdSeconds: 180,
        accuracyThresholdMeters: 50,
        switchHysteresisSeconds: 90,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
      }),
    );
    assert.equal(calls.length, 0);
  });
});
