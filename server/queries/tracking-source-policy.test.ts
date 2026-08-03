import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  resolveTenantTrackingPackage,
  isShipmentTrackingEntitled,
  resolveTenantTrackingSourcePolicy,
  getTenantTrackingSourcePolicy,
  TrackingSourcePolicyQueryError,
  type TrackingSourcePolicyQueryClient,
} from "./tracking-source-policy.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: TrackingSourcePolicyQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
    from() {
      throw new Error("not used in this fake");
    },
  } as unknown as TrackingSourcePolicyQueryClient;
  return { client, calls };
}

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): TrackingSourcePolicyQueryClient {
  return {
    from(table: string) {
      assert.equal(table, "tenant_tracking_source_policies");
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        async maybeSingle() {
          return response;
        },
      };
    },
    rpc() {
      throw new Error("not used in this fake");
    },
  } as unknown as TrackingSourcePolicyQueryClient;
}

describe("resolveTenantTrackingPackage", () => {
  test("parses a scalar composite-type response (not wrapped in an array)", async () => {
    const { client, calls } = fakeRpcClient({
      data: { enabled: true, package_code: "standard", max_tracked_vehicles: 50, max_mobile_sessions: 20, history_retention_days: 90, resolved_version_id: TENANT_ID },
      error: null,
    });
    const resolution = await resolveTenantTrackingPackage(client, TENANT_ID);
    assert.equal(resolution.enabled, true);
    assert.equal(resolution.packageCode, "standard");
    assert.equal(calls[0]?.fn, "resolve_tenant_tracking_package");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
  });

  test("throws TrackingSourcePolicyQueryError on an rpc error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => resolveTenantTrackingPackage(client, TENANT_ID), TrackingSourcePolicyQueryError);
  });
});

describe("isShipmentTrackingEntitled", () => {
  test("returns the raw boolean", async () => {
    const { client } = fakeRpcClient({ data: false, error: null });
    const entitled = await isShipmentTrackingEntitled(client, TENANT_ID);
    assert.equal(entitled, false);
  });

  test("throws on a non-boolean response", async () => {
    const { client } = fakeRpcClient({ data: "not-a-boolean", error: null });
    await assert.rejects(() => isShipmentTrackingEntitled(client, TENANT_ID), TrackingSourcePolicyQueryError);
  });
});

describe("resolveTenantTrackingSourcePolicy", () => {
  test("parses a table-shaped (array-wrapped) response and discloses isExplicit", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          tenant_id: TENANT_ID,
          default_source_priority: ["driver_mobile", "direct_device", "third_party_platform"],
          freshness_threshold_seconds: 300,
          accuracy_threshold_meters: 100,
          switch_hysteresis_seconds: 120,
          is_explicit: false,
        },
      ],
      error: null,
    });
    const resolved = await resolveTenantTrackingSourcePolicy(client, TENANT_ID);
    assert.equal(resolved.isExplicit, false);
    assert.equal(resolved.freshnessThresholdSeconds, 300);
  });
});

describe("getTenantTrackingSourcePolicy", () => {
  test("returns null when no explicit row exists", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const policy = await getTenantTrackingSourcePolicy(client, TENANT_ID);
    assert.equal(policy, null);
  });

  test("parses an explicit row when one exists", async () => {
    const client = fakeTableClient({
      data: {
        id: TENANT_ID,
        tenant_id: TENANT_ID,
        default_source_priority: ["direct_device", "driver_mobile"],
        freshness_threshold_seconds: 180,
        accuracy_threshold_meters: 50,
        switch_hysteresis_seconds: 90,
        record_version: 1,
        created_by: "tenant admin",
        created_at: "2026-08-03T00:00:00.000Z",
        updated_at: "2026-08-03T00:00:00.000Z",
      },
      error: null,
    });
    const policy = await getTenantTrackingSourcePolicy(client, TENANT_ID);
    assert.ok(policy);
    assert.equal(policy?.freshnessThresholdSeconds, 180);
  });
});
