import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWmsOutboundShipment,
  parseWmsShipmentPackage,
  parseWmsShipmentIssueLine,
  parseWmsBillingEligibilityEvent,
  CreateWmsOutboundShipmentInputSchema,
  AddPackageToShipmentInputSchema,
  ShipConfirmWmsOutboundShipmentInputSchema,
  CancelWmsOutboundShipmentInputSchema,
} from "./wms-outbound.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OUTBOUND_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const DOCK_LOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "923e4567-e89b-12d3-a456-426614174000";
const PACKAGE_ID = "a23e4567-e89b-12d3-a456-426614174000";
const PACKAGE_LINE_ID = "b23e4567-e89b-12d3-a456-426614174000";
const PICK_TASK_ID = "c23e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "d23e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "e23e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "f23e4567-e89b-12d3-a456-426614174000";

const SHIPMENT_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  outbound_order_id: OUTBOUND_ORDER_ID,
  owner_account_id: OWNER_ID,
  shipment_number: "WMSSHIP-2026-000001",
  idempotency_key: "idem-ship-1",
  status: "staging",
  dock_location_id: null,
  vehicle_ref: null,
  loaded_at: null,
  loaded_by_auth_user_id: null,
  loaded_by_label: null,
  load_movement_id: null,
  custody_confirmed_by_label: null,
  custody_confirmed_reason: null,
  custody_confirmed_at: null,
  shipped_at: null,
  shipped_by_auth_user_id: null,
  shipped_by_label: null,
  consumption_movement_id: null,
  is_partial_fulfillment: false,
  partial_fulfillment_reason: null,
  cancelled_at: null,
  cancelled_by_auth_user_id: null,
  cancelled_by_label: null,
  cancelled_reason: null,
  record_version: 1,
  created_at: "2026-08-04T00:00:00.000Z",
  updated_at: "2026-08-04T00:00:00.000Z",
};

describe("parseWmsOutboundShipment", () => {
  test("maps a staging snake_case row into the camelCase contract shape", () => {
    const shipment = parseWmsOutboundShipment(SHIPMENT_ROW);
    assert.equal(shipment.id, SHIPMENT_ID);
    assert.equal(shipment.status, "staging");
    assert.equal(shipment.dockLocationId, null);
    assert.equal(shipment.isPartialFulfillment, false);
    assert.equal(shipment.recordVersion, 1);
  });

  test("maps a fully shipped row, including custody/consumption/partial-fulfillment fields", () => {
    const shipment = parseWmsOutboundShipment({
      ...SHIPMENT_ROW,
      status: "shipped",
      dock_location_id: DOCK_LOCATION_ID,
      vehicle_ref: "TRUCK-001",
      loaded_at: "2026-08-04T01:00:00.000Z",
      load_movement_id: MOVEMENT_ID,
      custody_confirmed_by_label: "Driver Joko",
      custody_confirmed_reason: "handoff to carrier",
      custody_confirmed_at: "2026-08-04T02:00:00.000Z",
      shipped_at: "2026-08-04T02:00:00.000Z",
      consumption_movement_id: MOVEMENT_ID,
      is_partial_fulfillment: true,
      partial_fulfillment_reason: "backorder remainder ships later",
      record_version: 3,
    });
    assert.equal(shipment.status, "shipped");
    assert.equal(shipment.dockLocationId, DOCK_LOCATION_ID);
    assert.equal(shipment.custodyConfirmedByLabel, "Driver Joko");
    assert.equal(shipment.consumptionMovementId, MOVEMENT_ID);
    assert.equal(shipment.isPartialFulfillment, true);
    assert.equal(shipment.partialFulfillmentReason, "backorder remainder ships later");
  });

  test("rejects an invalid status value", () => {
    assert.throws(() => parseWmsOutboundShipment({ ...SHIPMENT_ROW, status: "bogus" }));
  });
});

describe("parseWmsShipmentPackage", () => {
  test("maps a membership row", () => {
    const row = parseWmsShipmentPackage({
      id: PACKAGE_ID,
      tenant_id: TENANT_ID,
      shipment_id: SHIPMENT_ID,
      package_id: PACKAGE_ID,
      idempotency_key: "idem-add-1",
      added_at: "2026-08-04T00:00:00.000Z",
      added_by_auth_user_id: ACTOR_ID,
      added_by_label: "rep",
    });
    assert.equal(row.shipmentId, SHIPMENT_ID);
    assert.equal(row.packageId, PACKAGE_ID);
  });
});

describe("parseWmsShipmentIssueLine", () => {
  test("maps a real traceability row carrying pick_task_id/reservation_id", () => {
    const row = parseWmsShipmentIssueLine({
      id: "011e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      shipment_id: SHIPMENT_ID,
      package_id: PACKAGE_ID,
      package_line_id: PACKAGE_LINE_ID,
      pick_task_id: PICK_TASK_ID,
      reservation_id: RESERVATION_ID,
      item_master_id: ITEM_ID,
      owner_account_id: OWNER_ID,
      uom_code: "PCS",
      lot_number: null,
      serial_number: null,
      expiry_date: null,
      quantity: "30",
      movement_id: MOVEMENT_ID,
      created_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.pickTaskId, PICK_TASK_ID);
    assert.equal(row.reservationId, RESERVATION_ID);
    assert.equal(row.quantity, 30);
  });
});

describe("parseWmsBillingEligibilityEvent", () => {
  test("maps a real event row, including the weight_by_uom aggregate", () => {
    const row = parseWmsBillingEligibilityEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: OWNER_ID,
      outbound_order_id: OUTBOUND_ORDER_ID,
      shipment_id: SHIPMENT_ID,
      idempotency_key: "idem-ship-1",
      package_count: 1,
      line_count: 1,
      total_quantity: "30",
      weight_by_uom: { KG: 5 },
      shipped_at: "2026-08-04T02:00:00.000Z",
      created_at: "2026-08-04T02:00:00.000Z",
    });
    assert.equal(row.packageCount, 1);
    assert.equal(row.totalQuantity, 30);
    assert.deepEqual(row.weightByUom, { KG: 5 });
  });

  test("defaults weight_by_uom to an empty object when absent", () => {
    const row = parseWmsBillingEligibilityEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: OWNER_ID,
      outbound_order_id: OUTBOUND_ORDER_ID,
      shipment_id: SHIPMENT_ID,
      idempotency_key: "idem-ship-1",
      package_count: 1,
      line_count: 1,
      total_quantity: "30",
      weight_by_uom: null,
      shipped_at: "2026-08-04T02:00:00.000Z",
      created_at: "2026-08-04T02:00:00.000Z",
    });
    assert.deepEqual(row.weightByUom, {});
  });
});

describe("mutation input schemas", () => {
  test("CreateWmsOutboundShipmentInputSchema requires a non-empty idempotency key", () => {
    assert.throws(() =>
      CreateWmsOutboundShipmentInputSchema.parse({
        outboundOrderId: OUTBOUND_ORDER_ID,
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
    const parsed = CreateWmsOutboundShipmentInputSchema.parse({
      outboundOrderId: OUTBOUND_ORDER_ID,
      idempotencyKey: "idem-ship-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.outboundOrderId, OUTBOUND_ORDER_ID);
  });

  test("AddPackageToShipmentInputSchema requires real UUIDs", () => {
    assert.throws(() =>
      AddPackageToShipmentInputSchema.parse({
        shipmentId: "not-a-uuid",
        packageId: PACKAGE_ID,
        idempotencyKey: "idem-add-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("ShipConfirmWmsOutboundShipmentInputSchema requires non-empty custody label and reason", () => {
    assert.throws(() =>
      ShipConfirmWmsOutboundShipmentInputSchema.parse({
        shipmentId: SHIPMENT_ID,
        custodyConfirmedByLabel: "",
        custodyConfirmedReason: "handoff",
        isPartialFulfillment: false,
        partialFulfillmentReason: null,
        idempotencyKey: "idem-confirm-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
    const parsed = ShipConfirmWmsOutboundShipmentInputSchema.parse({
      shipmentId: SHIPMENT_ID,
      custodyConfirmedByLabel: "Driver Joko",
      custodyConfirmedReason: "handoff to carrier",
      isPartialFulfillment: true,
      partialFulfillmentReason: "backorder remainder",
      idempotencyKey: "idem-confirm-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.isPartialFulfillment, true);
  });

  test("CancelWmsOutboundShipmentInputSchema requires a non-empty reason and positive expectedVersion", () => {
    assert.throws(() =>
      CancelWmsOutboundShipmentInputSchema.parse({
        shipmentId: SHIPMENT_ID,
        reason: "",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
    assert.throws(() =>
      CancelWmsOutboundShipmentInputSchema.parse({
        shipmentId: SHIPMENT_ID,
        reason: "customer cancelled order",
        expectedVersion: 0,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
