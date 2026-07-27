import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseDispatchReadiness,
  parseDispatchReadyQueueRow,
  parseDispatchCommand,
  parseBulkDispatchResultRow,
  DispatchShipmentOrderInputSchema,
  BulkDispatchShipmentOrdersInputSchema,
} from "./basic-dispatch.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const COMMAND_ID = "523e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "623e4567-e89b-12d3-a456-426614174000";
const SHIPPER_ID = "723e4567-e89b-12d3-a456-426614174000";

const BASE_SHIPMENT_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-0001",
  idempotency_key: "idem-1",
  status: "assigned",
  held_from_status: null,
  shipper_account_id: SHIPPER_ID,
  consignee_snapshot: {},
  notify_party_snapshot: null,
  cargo_service_snapshot: {},
  service_type: "FCL",
  mode: "sea",
  origin: "Jakarta",
  destination: "Singapore",
  planned_pickup_at: "2026-07-28T00:00:00.000Z",
  planned_delivery_at: null,
  basis_quantity: null,
  basis_weight_kg: null,
  basis_volume_cbm: null,
  allocated_quantity: null,
  allocated_weight_kg: null,
  allocated_volume_cbm: null,
  split_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("parseDispatchReadiness", () => {
  test("maps a ready row with zero blockers", () => {
    const readiness = parseDispatchReadiness({ is_ready: true, blockers: [] });
    assert.equal(readiness.isReady, true);
    assert.deepEqual(readiness.blockers, []);
  });

  test("maps a blocked row, preserving each blocker's code/detail", () => {
    const readiness = parseDispatchReadiness({
      is_ready: false,
      blockers: [{ code: "no_active_assignment", detail: null }],
    });
    assert.equal(readiness.isReady, false);
    assert.equal(readiness.blockers[0]?.code, "no_active_assignment");
  });
});

describe("parseDispatchReadyQueueRow", () => {
  test("maps every shipment_orders column plus is_ready/blockers", () => {
    const row = parseDispatchReadyQueueRow({ ...BASE_SHIPMENT_ROW, is_ready: true, blockers: [] });
    assert.equal(row.id, SHIPMENT_ID);
    assert.equal(row.status, "assigned");
    assert.equal(row.isReady, true);
    assert.deepEqual(row.blockers, []);
  });

  test("carries a real blocker list through for a not-ready row", () => {
    const row = parseDispatchReadyQueueRow({
      ...BASE_SHIPMENT_ROW,
      is_ready: false,
      blockers: [{ code: "missing_schedule", detail: null }],
    });
    assert.equal(row.isReady, false);
    assert.equal(row.blockers.length, 1);
  });
});

describe("parseDispatchCommand", () => {
  test("maps a real row, unwrapping the readiness_snapshot jsonb into isReady/blockers", () => {
    const command = parseDispatchCommand({
      id: COMMAND_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      command: "dispatch",
      readiness_snapshot: { is_ready: true, blockers: [] },
      idempotency_key: "idem-disp-1",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "rep",
      dispatched_at: "2026-07-27T09:00:00.000Z",
      created_at: "2026-07-27T09:00:00.000Z",
    });
    assert.equal(command.command, "dispatch");
    assert.equal(command.readinessSnapshot.isReady, true);
    assert.deepEqual(command.readinessSnapshot.blockers, []);
  });
});

describe("parseBulkDispatchResultRow", () => {
  test("maps a success row with null error fields", () => {
    const row = parseBulkDispatchResultRow({ shipment_order_id: SHIPMENT_ID, success: true, error_code: null, error_message: null });
    assert.equal(row.success, true);
    assert.equal(row.errorCode, null);
  });

  test("maps a failure row, preserving the error code/message", () => {
    const row = parseBulkDispatchResultRow({
      shipment_order_id: SHIPMENT_ID,
      success: false,
      error_code: "dispatch_not_ready",
      error_message: "dispatch_not_ready: shipment order is not ready to dispatch",
    });
    assert.equal(row.success, false);
    assert.equal(row.errorCode, "dispatch_not_ready");
  });
});

describe("DispatchShipmentOrderInputSchema", () => {
  test("requires a non-empty idempotencyKey", () => {
    assert.throws(() =>
      DispatchShipmentOrderInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        expectedVersion: 1,
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects a non-positive expectedVersion", () => {
    assert.throws(() =>
      DispatchShipmentOrderInputSchema.parse({
        shipmentOrderId: SHIPMENT_ID,
        expectedVersion: 0,
        idempotencyKey: "idem-disp-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("BulkDispatchShipmentOrdersInputSchema", () => {
  test("rejects an empty shipmentOrderIds array", () => {
    assert.throws(() =>
      BulkDispatchShipmentOrdersInputSchema.parse({
        shipmentOrderIds: [],
        idempotencyKeyPrefix: "idem-bulk",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects more than 50 ids", () => {
    const ids = Array.from({ length: 51 }, () => SHIPMENT_ID);
    assert.throws(() =>
      BulkDispatchShipmentOrdersInputSchema.parse({
        shipmentOrderIds: ids,
        idempotencyKeyPrefix: "idem-bulk",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts exactly 50 ids", () => {
    const ids = Array.from({ length: 50 }, () => SHIPMENT_ID);
    const parsed = BulkDispatchShipmentOrdersInputSchema.parse({
      shipmentOrderIds: ids,
      idempotencyKeyPrefix: "idem-bulk",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.shipmentOrderIds.length, 50);
  });
});
