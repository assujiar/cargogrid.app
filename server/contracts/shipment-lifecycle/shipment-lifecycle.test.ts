import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseShipmentStatusTransition,
  TransitionShipmentOrderInputSchema,
  GetShipmentStatusHistoryInputSchema,
} from "./shipment-lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const TRANSITION_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseShipmentStatusTransition", () => {
  test("maps a row with a reason and no evidence", () => {
    const transition = parseShipmentStatusTransition({
      id: TRANSITION_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      from_status: "planned",
      to_status: "held",
      reason: "customer requested a hold",
      evidence_ref: null,
      idempotency_key: "idem-1",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "rep",
      occurred_at: "2026-07-27T00:00:00.000Z",
    });
    assert.equal(transition.toStatus, "held");
    assert.equal(transition.reason, "customer requested a hold");
    assert.equal(transition.evidenceRef, null);
  });

  test("maps a row with evidence and no reason", () => {
    const transition = parseShipmentStatusTransition({
      id: TRANSITION_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      from_status: "in_transit",
      to_status: "delivered",
      reason: null,
      evidence_ref: "POD-0001",
      idempotency_key: "idem-2",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "rep",
      occurred_at: "2026-07-27T00:00:00.000Z",
    });
    assert.equal(transition.evidenceRef, "POD-0001");
    assert.equal(transition.reason, null);
  });
});

describe("TransitionShipmentOrderInputSchema", () => {
  test("requires a non-empty idempotencyKey", () => {
    assert.throws(() =>
      TransitionShipmentOrderInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        toStatus: "planned",
        expectedVersion: 1,
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects 'draft' as a transition target (never a real destination)", () => {
    assert.throws(() =>
      TransitionShipmentOrderInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        toStatus: "draft",
        expectedVersion: 1,
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("defaults reason/evidenceRef to null", () => {
    const parsed = TransitionShipmentOrderInputSchema.parse({
      shipmentOrderId: SHIPMENT_ID,
      toStatus: "planned",
      expectedVersion: 1,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.reason, null);
    assert.equal(parsed.evidenceRef, null);
  });
});

describe("GetShipmentStatusHistoryInputSchema", () => {
  test("requires a valid uuid shipmentOrderId", () => {
    assert.throws(() => GetShipmentStatusHistoryInputSchema.parse({ shipmentOrderId: "not-a-uuid", actorAuthUserId: ACTOR_ID }));
  });
});
