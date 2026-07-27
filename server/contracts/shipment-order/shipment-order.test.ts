import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseShipmentOrder,
  parseJobShipmentAllocationBalance,
  CreateShipmentOrderFromJobInputSchema,
  ConfirmShipmentOrderInputSchema,
  CancelShipmentOrderInputSchema,
} from "./shipment-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const BASE_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  idempotency_key: "idem-1",
  status: "draft",
  shipper_account_id: ACCOUNT_ID,
  consignee_snapshot: { legal_name: "Acme Shipping Co" },
  notify_party_snapshot: null,
  cargo_service_snapshot: { service_type: "ocean_freight" },
  service_type: "ocean_freight",
  mode: "sea",
  origin: "Jakarta",
  destination: "Surabaya",
  planned_pickup_at: null,
  planned_delivery_at: null,
  split_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("parseShipmentOrder", () => {
  test("maps a row with a declared basis", () => {
    const shipment = parseShipmentOrder({
      ...BASE_ROW,
      basis_quantity: 15,
      basis_weight_kg: 1500,
      basis_volume_cbm: 30,
      allocated_quantity: 10,
      allocated_weight_kg: 1000,
      allocated_volume_cbm: 20,
    });
    assert.equal(shipment.basisQuantity, 15);
    assert.equal(shipment.allocatedQuantity, 10);
    assert.equal(shipment.mode, "sea");
  });

  test("maps a split row with a null basis (only the first row declares it)", () => {
    const shipment = parseShipmentOrder({
      ...BASE_ROW,
      basis_quantity: null,
      basis_weight_kg: null,
      basis_volume_cbm: null,
      allocated_quantity: 3,
      allocated_weight_kg: 300,
      allocated_volume_cbm: 6,
      split_reason: "partial cargo ready earlier",
    });
    assert.equal(shipment.basisQuantity, null);
    assert.equal(shipment.splitReason, "partial cargo ready earlier");
  });
});

describe("parseJobShipmentAllocationBalance", () => {
  test("maps a null basis (advisory-only) distinct from a zero basis", () => {
    const balance = parseJobShipmentAllocationBalance({
      basis_quantity: null,
      basis_weight_kg: null,
      basis_volume_cbm: null,
      allocated_quantity: 0,
      allocated_weight_kg: 0,
      allocated_volume_cbm: 0,
      remaining_quantity: null,
      remaining_weight_kg: null,
      remaining_volume_cbm: null,
    });
    assert.equal(balance.basisQuantity, null);
    assert.equal(balance.remainingQuantity, null);
    assert.equal(balance.allocatedQuantity, 0);
  });

  test("maps a real established basis with remaining headroom", () => {
    const balance = parseJobShipmentAllocationBalance({
      basis_quantity: 15,
      basis_weight_kg: 1500,
      basis_volume_cbm: 30,
      allocated_quantity: 13,
      allocated_weight_kg: 1300,
      allocated_volume_cbm: 26,
      remaining_quantity: 2,
      remaining_weight_kg: 200,
      remaining_volume_cbm: 4,
    });
    assert.equal(balance.remainingQuantity, 2);
  });
});

describe("CreateShipmentOrderFromJobInputSchema", () => {
  test("requires a non-empty idempotencyKey", () => {
    assert.throws(() =>
      CreateShipmentOrderFromJobInputSchema.parse({
        jobOrderId: JOB_ORDER_ID,
        idempotencyKey: "",
        serviceType: "ocean_freight",
        mode: "sea",
        origin: "Jakarta",
        destination: "Surabaya",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects an unsupported mode", () => {
    assert.throws(() =>
      CreateShipmentOrderFromJobInputSchema.parse({
        jobOrderId: JOB_ORDER_ID,
        idempotencyKey: "idem-1",
        serviceType: "ocean_freight",
        mode: "rail",
        origin: "Jakarta",
        destination: "Surabaya",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("defaults consignee/notifyParty/allocation/basis fields to null", () => {
    const parsed = CreateShipmentOrderFromJobInputSchema.parse({
      jobOrderId: JOB_ORDER_ID,
      idempotencyKey: "idem-1",
      serviceType: "ocean_freight",
      mode: "sea",
      origin: "Jakarta",
      destination: "Surabaya",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.consignee, null);
    assert.equal(parsed.allocatedQuantity, null);
    assert.equal(parsed.basisQuantity, null);
  });
});

describe("ConfirmShipmentOrderInputSchema", () => {
  test("requires a positive expectedVersion", () => {
    assert.throws(() =>
      ConfirmShipmentOrderInputSchema.parse({ shipmentOrderId: SHIPMENT_ID, expectedVersion: 0, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });
});

describe("CancelShipmentOrderInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      CancelShipmentOrderInputSchema.parse({ shipmentOrderId: SHIPMENT_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });
});
