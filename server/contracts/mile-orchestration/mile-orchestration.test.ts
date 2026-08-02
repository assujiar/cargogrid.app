import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseShipmentLegTrackingPolicy,
  parseShipmentLegTrackingSession,
  parseResolvedLegTrackingPolicy,
  UpsertShipmentLegTrackingPolicyInputSchema,
  StartLegTrackingSessionInputSchema,
} from "./mile-orchestration.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "423e4567-e89b-12d3-a456-426614174000";
const RESOURCE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseShipmentLegTrackingPolicy", () => {
  test("maps a tracking-required policy", () => {
    const policy = parseShipmentLegTrackingPolicy({
      id: POLICY_ID,
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      tracking_required: true,
      allowed_sources: ["driver_mobile", "direct_device"],
      preferred_source: "direct_device",
      fallback_order: ["direct_device", "driver_mobile"],
      freshness_tolerance_seconds: 120,
      accuracy_tolerance_meters: 50,
      ping_interval_seconds: 30,
      start_trigger: "leg_dispatch",
      end_trigger: "leg_complete",
      geofence_policy: null,
      customer_visible: true,
      no_signal_escalation_seconds: 900,
      policy_version: 1,
      status: "active",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-02T00:00:00.000Z",
      updated_at: "2026-08-02T00:00:00.000Z",
    });
    assert.equal(policy.trackingRequired, true);
    assert.deepEqual(policy.fallbackOrder, ["direct_device", "driver_mobile"]);
  });

  test("maps the explicit not-required state with empty arrays", () => {
    const policy = parseShipmentLegTrackingPolicy({
      id: POLICY_ID,
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      tracking_required: false,
      allowed_sources: [],
      preferred_source: null,
      fallback_order: [],
      freshness_tolerance_seconds: null,
      accuracy_tolerance_meters: null,
      ping_interval_seconds: null,
      start_trigger: "leg_dispatch",
      end_trigger: "leg_complete",
      geofence_policy: null,
      customer_visible: false,
      no_signal_escalation_seconds: null,
      policy_version: 1,
      status: "active",
      record_version: 1,
      created_by: null,
      created_at: "2026-08-02T00:00:00.000Z",
      updated_at: "2026-08-02T00:00:00.000Z",
    });
    assert.equal(policy.trackingRequired, false);
    assert.equal(policy.preferredSource, null);
  });
});

describe("parseShipmentLegTrackingSession", () => {
  test("maps an active session with a false entitlement snapshot", () => {
    const session = parseShipmentLegTrackingSession({
      id: RESOURCE_ID,
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      policy_id: POLICY_ID,
      source_type: "driver_mobile",
      resource_kind: "driver",
      resource_master_id: RESOURCE_ID,
      device_id: null,
      tracking_entitled_at_start: false,
      status: "active",
      started_at: "2026-08-02T00:00:00.000Z",
      ended_at: null,
      end_reason: null,
      is_current: true,
      superseded_by_id: null,
      created_by: "rep",
      created_at: "2026-08-02T00:00:00.000Z",
    });
    assert.equal(session.status, "active");
    assert.equal(session.trackingEntitledAtStart, false);
  });

  test("maps a superseded (handed-off) session", () => {
    const session = parseShipmentLegTrackingSession({
      id: RESOURCE_ID,
      tenant_id: TENANT_ID,
      shipment_leg_id: LEG_ID,
      policy_id: POLICY_ID,
      source_type: "direct_device",
      resource_kind: "vehicle",
      resource_master_id: RESOURCE_ID,
      device_id: RESOURCE_ID,
      tracking_entitled_at_start: false,
      status: "ended",
      started_at: "2026-08-02T00:00:00.000Z",
      ended_at: "2026-08-02T01:00:00.000Z",
      end_reason: "handoff",
      is_current: false,
      superseded_by_id: POLICY_ID,
      created_by: "rep",
      created_at: "2026-08-02T00:00:00.000Z",
    });
    assert.equal(session.endReason, "handoff");
    assert.equal(session.supersededById, POLICY_ID);
  });
});

describe("parseResolvedLegTrackingPolicy", () => {
  test("maps an honest not-entitled resolution alongside a resolved source", () => {
    const resolved = parseResolvedLegTrackingPolicy({
      policy_id: POLICY_ID,
      tracking_required: true,
      tracking_entitled: false,
      eligible_sources: ["driver_mobile", "direct_device"],
      resolved_source: "direct_device",
      resolved_vehicle_master_id: RESOURCE_ID,
      resolved_driver_master_id: null,
      resolved_device_id: RESOURCE_ID,
      blocked_reason: null,
    });
    assert.equal(resolved.resolvedSource, "direct_device");
    assert.equal(resolved.trackingEntitled, false);
    assert.equal(resolved.blockedReason, null);
  });

  test("maps a no-eligible-source block", () => {
    const resolved = parseResolvedLegTrackingPolicy({
      policy_id: POLICY_ID,
      tracking_required: true,
      tracking_entitled: false,
      eligible_sources: [],
      resolved_source: null,
      resolved_vehicle_master_id: null,
      resolved_driver_master_id: null,
      resolved_device_id: null,
      blocked_reason: "no_eligible_source",
    });
    assert.equal(resolved.blockedReason, "no_eligible_source");
    assert.deepEqual(resolved.eligibleSources, []);
  });
});

describe("UpsertShipmentLegTrackingPolicyInputSchema", () => {
  test("rejects an unsupported source in allowedSources", () => {
    assert.throws(() =>
      UpsertShipmentLegTrackingPolicyInputSchema.parse({
        shipmentLegId: LEG_ID,
        trackingRequired: true,
        allowedSources: ["hybrid"],
        preferredSource: null,
        fallbackOrder: [],
        freshnessToleranceSeconds: null,
        accuracyToleranceMeters: null,
        pingIntervalSeconds: null,
        startTrigger: "leg_dispatch",
        endTrigger: "leg_complete",
        geofencePolicy: null,
        customerVisible: false,
        noSignalEscalationSeconds: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts a valid tracking-required input", () => {
    const parsed = UpsertShipmentLegTrackingPolicyInputSchema.parse({
      shipmentLegId: LEG_ID,
      trackingRequired: true,
      allowedSources: ["driver_mobile"],
      preferredSource: "driver_mobile",
      fallbackOrder: ["driver_mobile"],
      freshnessToleranceSeconds: 120,
      accuracyToleranceMeters: 50,
      pingIntervalSeconds: 30,
      startTrigger: "leg_dispatch",
      endTrigger: "leg_complete",
      geofencePolicy: null,
      customerVisible: true,
      noSignalEscalationSeconds: 900,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.preferredSource, "driver_mobile");
  });
});

describe("StartLegTrackingSessionInputSchema", () => {
  test("accepts a direct_device session with a device id", () => {
    const parsed = StartLegTrackingSessionInputSchema.parse({
      shipmentLegId: LEG_ID,
      sourceType: "direct_device",
      resourceKind: "vehicle",
      resourceMasterId: RESOURCE_ID,
      deviceId: RESOURCE_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.sourceType, "direct_device");
  });
});
