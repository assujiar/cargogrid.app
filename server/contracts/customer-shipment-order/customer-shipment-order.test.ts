import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerShipmentOrder,
  parseCustomerShipmentChangeRequest,
  CustomerShipmentOrderCursorSchema,
  RequestCustomerShipmentOrderChangeInputSchema,
  RespondToCustomerShipmentOrderChangeRequestInputSchema,
  SHIPMENT_ORDER_STATUSES,
  SHIPMENT_CHANGE_REQUEST_TYPES,
  SHIPMENT_CHANGE_REQUEST_STATUSES,
} from "./customer-shipment-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "623e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

const SHIPMENT_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  status: "confirmed",
  shipper_account_id: ACCOUNT_ID,
  consignee_snapshot: { name: "Acme" },
  notify_party_snapshot: null,
  cargo_service_snapshot: { description: "General cargo" },
  service_type: "ocean_freight",
  mode: "sea",
  origin: "Jakarta",
  destination: "Surabaya",
  planned_pickup_at: "2026-09-01T00:00:00.000Z",
  planned_delivery_at: "2026-09-10T00:00:00.000Z",
  allocated_quantity: 10,
  allocated_weight_kg: 1000,
  allocated_volume_cbm: 20,
  record_version: 1,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
};

const CHANGE_REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  shipment_order_id: SHIPMENT_ID,
  requested_by_auth_user_id: AUTH_USER_ID,
  request_type: "reschedule",
  details: "Please move pickup one day later",
  status: "submitted",
  idempotency_key: "change-1",
  record_version: 1,
  created_at: "2026-08-16T00:00:00.000Z",
  updated_at: "2026-08-16T00:00:00.000Z",
  staff_response: null,
  staff_responded_by: null,
  staff_responded_at: null,
};

describe("parseCustomerShipmentOrder", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerShipmentOrder(SHIPMENT_ROW);
    assert.equal(parsed.id, SHIPMENT_ID);
    assert.equal(parsed.jobOrderId, JOB_ORDER_ID);
    assert.equal(parsed.shipperAccountId, ACCOUNT_ID);
    assert.equal(parsed.status, "confirmed");
    assert.deepEqual(parsed.consigneeSnapshot, { name: "Acme" });
    assert.equal(parsed.allocatedWeightKg, 1000);
  });

  test("does not carry any staff-internal field (idempotency_key, owner_user_id, org_unit_id, created_by, split_reason, basis_*)", () => {
    const parsed = parseCustomerShipmentOrder(SHIPMENT_ROW) as unknown as Record<string, unknown>;
    for (const forbidden of ["idempotencyKey", "ownerUserId", "orgUnitId", "createdBy", "splitReason", "basisQuantity", "basisWeightKg", "basisVolumeCbm"]) {
      assert.equal(parsed[forbidden], undefined, `expected ${forbidden} to be absent from the customer-safe projection`);
    }
  });

  test("defaults nullable snapshot/date fields", () => {
    const parsed = parseCustomerShipmentOrder({ ...SHIPMENT_ROW, notify_party_snapshot: undefined, planned_pickup_at: undefined, allocated_quantity: undefined });
    assert.equal(parsed.notifyPartySnapshot, null);
    assert.equal(parsed.plannedPickupAt, null);
    assert.equal(parsed.allocatedQuantity, null);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => parseCustomerShipmentOrder({ ...SHIPMENT_ROW, status: "not_a_real_status" }));
  });

  test("every real status is exactly the migration's 3-value set", () => {
    assert.deepEqual([...SHIPMENT_ORDER_STATUSES], ["draft", "confirmed", "cancelled"]);
  });
});

describe("CustomerShipmentOrderCursorSchema", () => {
  test("accepts an empty cursor (first page)", () => {
    assert.doesNotThrow(() => CustomerShipmentOrderCursorSchema.parse({}));
  });

  test("rejects a cursorId supplied without cursorUpdatedAt", () => {
    assert.throws(() => CustomerShipmentOrderCursorSchema.parse({ cursorId: SHIPMENT_ID }));
  });
});

describe("parseCustomerShipmentChangeRequest", () => {
  test("maps every column, camelCased", () => {
    const parsed = parseCustomerShipmentChangeRequest(CHANGE_REQUEST_ROW);
    assert.equal(parsed.id, REQUEST_ID);
    assert.equal(parsed.shipmentOrderId, SHIPMENT_ID);
    assert.equal(parsed.requestType, "reschedule");
    assert.equal(parsed.status, "submitted");
    assert.equal(parsed.staffResponse, null);
  });

  test("every real request type is exactly the migration's 3-value set", () => {
    assert.deepEqual([...SHIPMENT_CHANGE_REQUEST_TYPES], ["reschedule", "cancel", "other"]);
  });

  test("every real status is exactly the migration's 4-value set", () => {
    assert.deepEqual([...SHIPMENT_CHANGE_REQUEST_STATUSES], ["submitted", "acknowledged", "resolved", "rejected"]);
  });

  test("maps a staff-responded row", () => {
    const parsed = parseCustomerShipmentChangeRequest({ ...CHANGE_REQUEST_ROW, status: "acknowledged", staff_response: "Looking into it", staff_responded_by: "ops-staff", staff_responded_at: "2026-08-17T00:00:00.000Z" });
    assert.equal(parsed.status, "acknowledged");
    assert.equal(parsed.staffResponse, "Looking into it");
  });
});

describe("RequestCustomerShipmentOrderChangeInputSchema", () => {
  test("accepts a minimal valid input", () => {
    const parsed = RequestCustomerShipmentOrderChangeInputSchema.parse({
      tenantId: TENANT_ID,
      shipmentOrderId: SHIPMENT_ID,
      requestType: "reschedule",
      details: "Move pickup later",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(parsed.requestType, "reschedule");
  });

  test("rejects an empty details string", () => {
    assert.throws(() =>
      RequestCustomerShipmentOrderChangeInputSchema.parse({
        tenantId: TENANT_ID,
        shipmentOrderId: SHIPMENT_ID,
        requestType: "cancel",
        details: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "x",
      }),
    );
  });

  test("rejects an unrecognized requestType", () => {
    assert.throws(() =>
      RequestCustomerShipmentOrderChangeInputSchema.parse({
        tenantId: TENANT_ID,
        shipmentOrderId: SHIPMENT_ID,
        requestType: "not_a_real_type",
        details: "x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "x",
      }),
    );
  });
});

describe("RespondToCustomerShipmentOrderChangeRequestInputSchema", () => {
  test("accepts a valid staff response", () => {
    const parsed = RespondToCustomerShipmentOrderChangeRequestInputSchema.parse({
      changeRequestId: REQUEST_ID,
      expectedVersion: 1,
      toStatus: "acknowledged",
      staffResponse: "Looking into it",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "ops-staff",
    });
    assert.equal(parsed.toStatus, "acknowledged");
  });

  test("rejects an empty staffResponse", () => {
    assert.throws(() =>
      RespondToCustomerShipmentOrderChangeRequestInputSchema.parse({
        changeRequestId: REQUEST_ID,
        expectedVersion: 1,
        toStatus: "resolved",
        staffResponse: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "x",
      }),
    );
  });

  test("rejects 'submitted' as a toStatus (staff may only move a request forward)", () => {
    assert.throws(() =>
      RespondToCustomerShipmentOrderChangeRequestInputSchema.parse({
        changeRequestId: REQUEST_ID,
        expectedVersion: 1,
        toStatus: "submitted",
        staffResponse: "x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "x",
      }),
    );
  });
});
