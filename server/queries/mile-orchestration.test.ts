import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getShipmentLegTrackingPolicy, resolveLegTrackingPolicy, MileOrchestrationQueryError } from "./mile-orchestration.ts";
import type { MileOrchestrationQueryTableClient } from "./mile-orchestration.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEG_ID = "323e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("getShipmentLegTrackingPolicy", () => {
  test("maps the single policy row for a leg", async () => {
    const client = {
      from() {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          maybeSingle() {
            return Promise.resolve({
              data: {
                id: POLICY_ID,
                tenant_id: TENANT_ID,
                shipment_leg_id: LEG_ID,
                tracking_required: true,
                allowed_sources: ["driver_mobile"],
                preferred_source: "driver_mobile",
                fallback_order: ["driver_mobile"],
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
              },
              error: null,
            });
          },
        };
      },
      async rpc() {
        throw new Error("not used in this fake");
      },
    } as unknown as MileOrchestrationQueryTableClient;
    const policy = await getShipmentLegTrackingPolicy(client, LEG_ID);
    assert.equal(policy?.trackingRequired, true);
  });

  test("returns null when no policy is defined yet", async () => {
    const client = {
      from() {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          maybeSingle() {
            return Promise.resolve({ data: null, error: null });
          },
        };
      },
      async rpc() {
        throw new Error("not used");
      },
    } as unknown as MileOrchestrationQueryTableClient;
    const policy = await getShipmentLegTrackingPolicy(client, LEG_ID);
    assert.equal(policy, null);
  });

  test("surfaces a real query error as MileOrchestrationQueryError", async () => {
    const client = {
      from() {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          maybeSingle() {
            return Promise.resolve({ data: null, error: { message: "connection reset" } });
          },
        };
      },
      async rpc() {
        throw new Error("not used");
      },
    } as unknown as MileOrchestrationQueryTableClient;
    await assert.rejects(() => getShipmentLegTrackingPolicy(client, LEG_ID), MileOrchestrationQueryError);
  });
});

describe("resolveLegTrackingPolicy", () => {
  test("calls resolve_leg_tracking_policy and maps the resolved projection", async () => {
    const client = {
      from() {
        throw new Error("not used in this fake");
      },
      async rpc(fn: string, args: Record<string, unknown>) {
        assert.equal(fn, "resolve_leg_tracking_policy");
        assert.equal(args.p_shipment_leg_id, LEG_ID);
        return {
          data: [
            {
              policy_id: POLICY_ID,
              tracking_required: true,
              tracking_entitled: false,
              eligible_sources: ["driver_mobile"],
              resolved_source: "driver_mobile",
              resolved_vehicle_master_id: null,
              resolved_driver_master_id: TENANT_ID,
              resolved_device_id: null,
              blocked_reason: null,
            },
          ],
          error: null,
        };
      },
    } as unknown as MileOrchestrationQueryTableClient;
    const resolved = await resolveLegTrackingPolicy(client, { shipmentLegId: LEG_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(resolved.resolvedSource, "driver_mobile");
    assert.equal(resolved.trackingEntitled, false);
  });

  test("throws when the RPC returns no row", async () => {
    const client = {
      from() {
        throw new Error("not used");
      },
      async rpc() {
        return { data: [], error: null };
      },
    } as unknown as MileOrchestrationQueryTableClient;
    await assert.rejects(() => resolveLegTrackingPolicy(client, { shipmentLegId: LEG_ID, actorAuthUserId: ACTOR_ID }), MileOrchestrationQueryError);
  });
});
