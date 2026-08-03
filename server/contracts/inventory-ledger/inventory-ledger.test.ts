import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseInventoryMovement,
  parseInventoryMovementLine,
  parseInventoryBalance,
  parseInventoryReservation,
  PostInventoryMovementInputSchema,
  ReverseInventoryMovementInputSchema,
  InventoryMovementSchema,
} from "./inventory-ledger.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "923e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "a23e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "b23e4567-e89b-12d3-a456-426614174000";

describe("parseInventoryMovement", () => {
  test("maps an opening-balance header row", () => {
    const movement = parseInventoryMovement({
      id: MOVEMENT_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      movement_type: "opening_balance",
      source_type: "opening_balance",
      source_id: null,
      idempotency_key: "idem-open-1",
      corrects_movement_id: null,
      reason: null,
      occurred_at: "2026-08-03T00:00:00.000Z",
      posted_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(movement.movementType, "opening_balance");
    assert.equal(movement.correctsMovementId, null);
  });

  test("maps a reversal header row with corrects_movement_id set", () => {
    const movement = parseInventoryMovement({
      id: LINE_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      movement_type: "reversal",
      source_type: "reversal",
      source_id: MOVEMENT_ID,
      idempotency_key: "idem-reverse-1",
      corrects_movement_id: MOVEMENT_ID,
      reason: "wrong quantity entered",
      occurred_at: "2026-08-03T00:00:00.000Z",
      posted_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(movement.correctsMovementId, MOVEMENT_ID);
  });

  test("rejects an invalid movement_type via the schema", () => {
    assert.throws(() =>
      InventoryMovementSchema.parse({
        id: MOVEMENT_ID,
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        movementType: "not_a_real_type",
        sourceType: "manual",
        sourceId: null,
        idempotencyKey: "idem-1",
        correctsMovementId: null,
        reason: null,
        occurredAt: "2026-08-03T00:00:00.000Z",
        postedBy: "rep",
        createdAt: "2026-08-03T00:00:00.000Z",
      }),
    );
  });
});

describe("parseInventoryMovementLine", () => {
  test("maps a full dimension tuple, coercing numeric signed_quantity", () => {
    const line = parseInventoryMovementLine({
      id: LINE_ID,
      tenant_id: TENANT_ID,
      movement_id: MOVEMENT_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: ACCOUNT_ID,
      item_master_id: ITEM_ID,
      location_id: LOCATION_ID,
      uom_code: "PCS",
      signed_quantity: "-20",
      lot_number: null,
      serial_number: null,
      expiry_date: null,
      status: "on_hand",
      created_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(line.signedQuantity, -20);
    assert.equal(line.status, "on_hand");
  });
});

describe("parseInventoryBalance", () => {
  test("maps on_hand/reserved/held/available, coercing numeric columns", () => {
    const balance = parseInventoryBalance({
      id: BALANCE_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: ACCOUNT_ID,
      item_master_id: ITEM_ID,
      location_id: LOCATION_ID,
      lot_number: null,
      serial_number: null,
      status: "on_hand",
      on_hand: "100",
      reserved: "10",
      held: "0",
      available: "90",
      record_version: 2,
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(balance.onHand, 100);
    assert.equal(balance.available, 90);
  });
});

describe("parseInventoryReservation", () => {
  test("maps an active reservation row", () => {
    const reservation = parseInventoryReservation({
      id: RESERVATION_ID,
      tenant_id: TENANT_ID,
      balance_id: BALANCE_ID,
      reserved_quantity: "5",
      status: "active",
      source_type: "manual",
      source_id: null,
      idempotency_key: "idem-reserve-1",
      released_reason: null,
      consumed_movement_id: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(reservation.status, "active");
    assert.equal(reservation.reservedQuantity, 5);
  });
});

describe("PostInventoryMovementInputSchema", () => {
  test("requires at least one line", () => {
    assert.throws(() =>
      PostInventoryMovementInputSchema.parse({
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        movementType: "opening_balance",
        sourceType: "opening_balance",
        idempotencyKey: "idem-1",
        lines: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects a zero signed_quantity line", () => {
    assert.throws(() =>
      PostInventoryMovementInputSchema.parse({
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        movementType: "opening_balance",
        sourceType: "opening_balance",
        idempotencyKey: "idem-1",
        lines: [{ ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: 0 }],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts a well-formed transfer with two lines", () => {
    const parsed = PostInventoryMovementInputSchema.parse({
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      movementType: "transfer",
      sourceType: "manual",
      idempotencyKey: "idem-transfer-1",
      lines: [
        { ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: -30 },
        { ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, uomCode: "PCS", signedQuantity: 30 },
      ],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.lines.length, 2);
  });
});

describe("ReverseInventoryMovementInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      ReverseInventoryMovementInputSchema.parse({
        movementId: MOVEMENT_ID,
        idempotencyKey: "idem-reverse-1",
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
