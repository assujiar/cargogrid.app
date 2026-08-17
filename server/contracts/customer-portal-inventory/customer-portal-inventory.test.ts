import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseCustomerPortalInventoryBalance, parseCustomerPortalWarehouseEligibility, CustomerPortalInventoryCursorSchema } from "./customer-portal-inventory.ts";

const WAREHOUSE_ID = "223e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "323e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "423e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "623e4567-e89b-12d3-a456-426614174000";
const ELIGIBILITY_ID = "d23e4567-e89b-12d3-a456-426614174000";

describe("parseCustomerPortalInventoryBalance", () => {
  test("maps a full balance row", () => {
    const row = parseCustomerPortalInventoryBalance({
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
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(row.onHand, 10);
    assert.equal(row.reserved, 2);
    assert.equal(row.available, 8);
    assert.equal(row.serialNumber, null);
  });

  test("rejects a row missing a required (non-nullable) field", () => {
    assert.throws(() =>
      parseCustomerPortalInventoryBalance({
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
        updated_at: "2026-08-17T00:00:00.000Z",
      }),
    );
  });
});

describe("parseCustomerPortalWarehouseEligibility", () => {
  test("maps an active grant", () => {
    const row = parseCustomerPortalWarehouseEligibility({
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
    const row = parseCustomerPortalWarehouseEligibility({
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

describe("CustomerPortalInventoryCursorSchema", () => {
  test("accepts both cursor fields omitted (first page)", () => {
    assert.doesNotThrow(() => CustomerPortalInventoryCursorSchema.parse({}));
  });

  test("accepts both cursor fields supplied together", () => {
    assert.doesNotThrow(() => CustomerPortalInventoryCursorSchema.parse({ cursorUpdatedAt: "2026-08-17T00:00:00.000Z", cursorId: BALANCE_ID }));
  });

  test("rejects cursorId supplied without cursorUpdatedAt (a half-cursor must fail loud, not silently return an empty page)", () => {
    assert.throws(() => CustomerPortalInventoryCursorSchema.parse({ cursorId: BALANCE_ID }));
  });

  test("accepts cursorUpdatedAt supplied alone (matches the RPC's own no-cursor signal being cursorId=null)", () => {
    assert.doesNotThrow(() => CustomerPortalInventoryCursorSchema.parse({ cursorUpdatedAt: "2026-08-17T00:00:00.000Z" }));
  });
});
