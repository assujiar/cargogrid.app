import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCustomerInventoryBalance,
  parseCustomerLotIdentity,
  parseCustomerSerialIdentity,
  parseCustomerOutboundOrder,
  parseCustomerOutboundOrderLine,
  parseCustomerInventoryMovementSummary,
  parseCustomerWarehouseEligibility,
  ExportCustomerInventorySnapshotInputSchema,
  CustomerInventoryCursorSchema,
} from "./customer-inventory-access.ts";

const WAREHOUSE_ID = "223e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "423e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "623e4567-e89b-12d3-a456-426614174000";
const LOT_ID = "723e4567-e89b-12d3-a456-426614174000";
const SERIAL_ID = "823e4567-e89b-12d3-a456-426614174000";
const ORDER_ID = "923e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "a23e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "b23e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_LINE_ID = "c23e4567-e89b-12d3-a456-426614174000";
const ELIGIBILITY_ID = "d23e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "e23e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "f23e4567-e89b-12d3-a456-426614174000";

describe("parseCustomerInventoryBalance", () => {
  test("maps a full balance row", () => {
    const row = parseCustomerInventoryBalance({
      id: BALANCE_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: OWNER_ID,
      item_master_id: ITEM_ID,
      location_id: LOCATION_ID,
      lot_number: "LOT-1",
      serial_number: null,
      status: "on_hand",
      on_hand: "10",
      reserved: "2",
      held: "0",
      available: "8",
      record_version: 1,
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.onHand, 10);
    assert.equal(row.reserved, 2);
    assert.equal(row.available, 8);
    assert.equal(row.serialNumber, null);
  });

  test("rejects a row missing a required (non-nullable) field", () => {
    assert.throws(() =>
      parseCustomerInventoryBalance({
        id: BALANCE_ID,
        warehouse_id: WAREHOUSE_ID,
        owner_account_id: OWNER_ID,
        item_master_id: ITEM_ID,
        location_id: LOCATION_ID,
        // status omitted -- required, not defaulted by the parse function.
        on_hand: "10",
        reserved: "0",
        held: "0",
        available: "10",
        record_version: 1,
        updated_at: "2026-08-04T00:00:00.000Z",
      }),
    );
  });
});

describe("parseCustomerLotIdentity", () => {
  test("maps a held lot with a real hold_reason", () => {
    const row = parseCustomerLotIdentity({
      id: LOT_ID,
      owner_account_id: OWNER_ID,
      item_master_id: ITEM_ID,
      lot_number: "LOT-1",
      manufacture_date: "2026-01-01",
      expiry_date: "2026-12-01",
      status: "held",
      hold_reason: "quality hold",
      record_version: 1,
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.status, "held");
    assert.equal(row.holdReason, "quality hold");
  });

  test("never carries parent_lot_id/source_type/source_id fields even if present on the raw row", () => {
    const row = parseCustomerLotIdentity({
      id: LOT_ID,
      owner_account_id: OWNER_ID,
      item_master_id: ITEM_ID,
      lot_number: "LOT-1",
      manufacture_date: null,
      expiry_date: null,
      status: "active",
      hold_reason: null,
      record_version: 1,
      updated_at: "2026-08-04T00:00:00.000Z",
      parent_lot_id: "should-be-ignored",
      source_type: "should-be-ignored",
    });
    assert.equal((row as Record<string, unknown>).parent_lot_id, undefined);
    assert.equal((row as Record<string, unknown>).source_type, undefined);
  });
});

describe("parseCustomerSerialIdentity", () => {
  test("maps a serial identity row", () => {
    const row = parseCustomerSerialIdentity({
      id: SERIAL_ID,
      owner_account_id: OWNER_ID,
      item_master_id: ITEM_ID,
      serial_number: "SN-1",
      lot_number: null,
      manufacture_date: null,
      expiry_date: null,
      status: "active",
      hold_reason: null,
      record_version: 1,
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.serialNumber, "SN-1");
    assert.equal(row.status, "active");
  });
});

describe("parseCustomerOutboundOrder", () => {
  test("maps an outbound order row", () => {
    const row = parseCustomerOutboundOrder({
      id: ORDER_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: OWNER_ID,
      outbound_number: "OUT-1",
      source_type: "manual",
      requested_ship_date: "2026-08-10",
      status: "draft",
      cancelled_reason: null,
      record_version: 1,
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.status, "draft");
    assert.equal(row.sourceType, "manual");
  });
});

describe("parseCustomerOutboundOrderLine", () => {
  test("maps an outbound order line row and excludes notes", () => {
    const row = parseCustomerOutboundOrderLine({
      id: LINE_ID,
      outbound_order_id: ORDER_ID,
      line_number: 1,
      item_master_id: ITEM_ID,
      requested_uom_code: "PCS",
      requested_quantity: "5",
      lot_controlled: false,
      serial_controlled: false,
      expiry_controlled: false,
      record_version: 1,
      updated_at: "2026-08-04T00:00:00.000Z",
      notes: "should-be-ignored",
    });
    assert.equal(row.requestedQuantity, 5);
    assert.equal((row as Record<string, unknown>).notes, undefined);
  });
});

describe("parseCustomerInventoryMovementSummary", () => {
  test("maps a movement summary row and excludes source_type/posted_by", () => {
    const row = parseCustomerInventoryMovementSummary({
      id: MOVEMENT_LINE_ID,
      movement_id: MOVEMENT_ID,
      movement_type: "opening_balance",
      occurred_at: "2026-08-04T00:00:00.000Z",
      item_master_id: ITEM_ID,
      warehouse_id: WAREHOUSE_ID,
      signed_quantity: "10",
      lot_number: null,
      serial_number: null,
      source_type: "should-be-ignored",
      posted_by: "should-be-ignored",
    });
    assert.equal(row.movementType, "opening_balance");
    assert.equal(row.signedQuantity, 10);
    assert.equal((row as Record<string, unknown>).source_type, undefined);
    assert.equal((row as Record<string, unknown>).posted_by, undefined);
  });
});

describe("parseCustomerWarehouseEligibility", () => {
  test("maps an active grant", () => {
    const row = parseCustomerWarehouseEligibility({
      id: ELIGIBILITY_ID,
      warehouse_id: WAREHOUSE_ID,
      customer_account_id: OWNER_ID,
      status: "active",
      granted_at: "2026-08-01T00:00:00.000Z",
      revoked_at: null,
      revoked_reason: null,
      record_version: 1,
    });
    assert.equal(row.status, "active");
    assert.equal(row.revokedReason, null);
  });

  test("maps a revoked grant with its own reason and excludes granted_by", () => {
    const row = parseCustomerWarehouseEligibility({
      id: ELIGIBILITY_ID,
      warehouse_id: WAREHOUSE_ID,
      customer_account_id: OWNER_ID,
      status: "revoked",
      granted_at: "2026-08-01T00:00:00.000Z",
      revoked_at: "2026-08-04T00:00:00.000Z",
      revoked_reason: "contract ended",
      record_version: 2,
      granted_by: "should-be-ignored",
    });
    assert.equal(row.status, "revoked");
    assert.equal(row.revokedReason, "contract ended");
    assert.equal((row as Record<string, unknown>).granted_by, undefined);
  });
});

describe("CustomerInventoryCursorSchema", () => {
  test("accepts both cursor fields omitted (first page)", () => {
    assert.doesNotThrow(() => CustomerInventoryCursorSchema.parse({}));
  });

  test("accepts both cursor fields supplied together", () => {
    assert.doesNotThrow(() => CustomerInventoryCursorSchema.parse({ cursorUpdatedAt: "2026-08-04T00:00:00.000Z", cursorId: BALANCE_ID }));
  });

  test("rejects cursorId supplied without cursorUpdatedAt (correctness-review finding: a half-cursor must fail loud, not silently return an empty page)", () => {
    assert.throws(() => CustomerInventoryCursorSchema.parse({ cursorId: BALANCE_ID }));
  });

  test("accepts cursorUpdatedAt supplied alone (matches the RPC's own no-cursor signal being cursorId=null)", () => {
    assert.doesNotThrow(() => CustomerInventoryCursorSchema.parse({ cursorUpdatedAt: "2026-08-04T00:00:00.000Z" }));
  });
});

describe("ExportCustomerInventorySnapshotInputSchema", () => {
  test("accepts the minimal required shape", () => {
    const parsed = ExportCustomerInventorySnapshotInputSchema.parse({
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
    });
    assert.equal(parsed.tenantId, TENANT_ID);
    assert.equal(parsed.warehouseId, undefined);
  });

  test("accepts the full shape with filters/limit/actorLabel", () => {
    const parsed = ExportCustomerInventorySnapshotInputSchema.parse({
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      warehouseId: WAREHOUSE_ID,
      itemMasterId: ITEM_ID,
      limit: 200,
      actorLabel: "customer-alpha",
    });
    assert.equal(parsed.limit, 200);
    assert.equal(parsed.actorLabel, "customer-alpha");
  });

  test("rejects a non-uuid tenantId", () => {
    assert.throws(() => ExportCustomerInventorySnapshotInputSchema.parse({ tenantId: "not-a-uuid", actorAuthUserId: ACTOR_ID }));
  });
});
