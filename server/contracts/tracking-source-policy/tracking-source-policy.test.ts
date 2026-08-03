import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseTrackingPackageResolution,
  parseTenantTrackingSourcePolicy,
  parseResolvedTenantTrackingSourcePolicy,
  UpsertTenantTrackingSourcePolicyInputSchema,
} from "./tracking-source-policy.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseTrackingPackageResolution", () => {
  test("maps the honest all-default row before any package is assigned", () => {
    const resolution = parseTrackingPackageResolution({
      enabled: false,
      package_code: null,
      max_tracked_vehicles: null,
      max_mobile_sessions: null,
      history_retention_days: null,
      resolved_version_id: null,
    });
    assert.equal(resolution.enabled, false);
    assert.equal(resolution.packageCode, null);
  });

  test("maps a resolved standard package", () => {
    const resolution = parseTrackingPackageResolution({
      enabled: true,
      package_code: "standard",
      max_tracked_vehicles: 50,
      max_mobile_sessions: 20,
      history_retention_days: 90,
      resolved_version_id: VERSION_ID,
    });
    assert.equal(resolution.enabled, true);
    assert.equal(resolution.packageCode, "standard");
    assert.equal(resolution.maxTrackedVehicles, 50);
    assert.equal(resolution.resolvedVersionId, VERSION_ID);
  });
});

describe("parseTenantTrackingSourcePolicy", () => {
  test("maps an explicit tenant policy row", () => {
    const policy = parseTenantTrackingSourcePolicy({
      id: POLICY_ID,
      tenant_id: TENANT_ID,
      default_source_priority: ["direct_device", "driver_mobile"],
      freshness_threshold_seconds: 180,
      accuracy_threshold_meters: 50,
      switch_hysteresis_seconds: 90,
      record_version: 1,
      created_by: "tenant admin",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.deepEqual(policy.defaultSourcePriority, ["direct_device", "driver_mobile"]);
    assert.equal(policy.freshnessThresholdSeconds, 180);
  });
});

describe("parseResolvedTenantTrackingSourcePolicy", () => {
  test("discloses the system default via isExplicit=false", () => {
    const resolved = parseResolvedTenantTrackingSourcePolicy({
      tenant_id: TENANT_ID,
      default_source_priority: ["driver_mobile", "direct_device", "third_party_platform"],
      freshness_threshold_seconds: 300,
      accuracy_threshold_meters: 100,
      switch_hysteresis_seconds: 120,
      is_explicit: false,
    });
    assert.equal(resolved.isExplicit, false);
    assert.deepEqual(resolved.defaultSourcePriority, ["driver_mobile", "direct_device", "third_party_platform"]);
  });

  test("discloses an explicit tenant override via isExplicit=true", () => {
    const resolved = parseResolvedTenantTrackingSourcePolicy({
      tenant_id: TENANT_ID,
      default_source_priority: ["direct_device", "driver_mobile"],
      freshness_threshold_seconds: 180,
      accuracy_threshold_meters: 50,
      switch_hysteresis_seconds: 90,
      is_explicit: true,
    });
    assert.equal(resolved.isExplicit, true);
  });
});

describe("UpsertTenantTrackingSourcePolicyInputSchema", () => {
  test("accepts a valid input", () => {
    const parsed = UpsertTenantTrackingSourcePolicyInputSchema.parse({
      tenantId: TENANT_ID,
      defaultSourcePriority: ["direct_device", "driver_mobile"],
      freshnessThresholdSeconds: 180,
      accuracyThresholdMeters: 50,
      switchHysteresisSeconds: 90,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant admin",
    });
    assert.equal(parsed.freshnessThresholdSeconds, 180);
  });

  test("rejects an empty source priority array", () => {
    assert.throws(() =>
      UpsertTenantTrackingSourcePolicyInputSchema.parse({
        tenantId: TENANT_ID,
        defaultSourcePriority: [],
        freshnessThresholdSeconds: 180,
        accuracyThresholdMeters: 50,
        switchHysteresisSeconds: 90,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
      }),
    );
  });

  test("rejects an unsupported source type", () => {
    assert.throws(() =>
      UpsertTenantTrackingSourcePolicyInputSchema.parse({
        tenantId: TENANT_ID,
        defaultSourcePriority: ["satellite"],
        freshnessThresholdSeconds: 180,
        accuracyThresholdMeters: 50,
        switchHysteresisSeconds: 90,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
      }),
    );
  });

  test("rejects a non-positive freshness threshold", () => {
    assert.throws(() =>
      UpsertTenantTrackingSourcePolicyInputSchema.parse({
        tenantId: TENANT_ID,
        defaultSourcePriority: ["driver_mobile"],
        freshnessThresholdSeconds: 0,
        accuracyThresholdMeters: 50,
        switchHysteresisSeconds: 90,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tenant admin",
      }),
    );
  });
});
