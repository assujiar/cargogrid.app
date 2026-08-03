import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseItemControlPolicyVersion,
  parseLotIdentity,
  parseSerialIdentity,
  parseTraceEvent,
  parseAllocationCandidate,
  CreateItemControlPolicyVersionDraftInputSchema,
  RegisterLotIdentityInputSchema,
  RegisterSerialIdentityInputSchema,
  SetLotIdentityStatusInputSchema,
} from "./lot-batch-serial.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "a23e4567-e89b-12d3-a456-426614174000";
const LOT_ID = "b23e4567-e89b-12d3-a456-426614174000";
const SERIAL_ID = "c23e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "d23e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "e23e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "f23e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "023e4567-e89b-12d3-a456-426614174001";

describe("parseItemControlPolicyVersion", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const policy = parseItemControlPolicyVersion({
      id: POLICY_ID,
      tenant_id: TENANT_ID,
      item_master_id: ITEM_ID,
      owner_account_id: OWNER_ID,
      allocation_rule: "fefo",
      hold_on_unknown_lot: true,
      near_expiry_warning_days: 14,
      status: "draft",
      supersedes_version_id: null,
      effective_from: "2026-08-03T00:00:00.000Z",
      record_version: 1,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(policy.allocationRule, "fefo");
    assert.equal(policy.nearExpiryWarningDays, 14);
    assert.equal(policy.status, "draft");
  });

  test("rejects an unrecognized allocation rule", () => {
    assert.throws(() =>
      parseItemControlPolicyVersion({
        id: POLICY_ID,
        tenant_id: TENANT_ID,
        item_master_id: ITEM_ID,
        owner_account_id: OWNER_ID,
        allocation_rule: "lifo",
        hold_on_unknown_lot: true,
        near_expiry_warning_days: null,
        status: "draft",
        supersedes_version_id: null,
        effective_from: "2026-08-03T00:00:00.000Z",
        record_version: 1,
        created_at: "2026-08-03T00:00:00.000Z",
        updated_at: "2026-08-03T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLotIdentity", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const lot = parseLotIdentity({
      id: LOT_ID,
      tenant_id: TENANT_ID,
      owner_account_id: OWNER_ID,
      item_master_id: ITEM_ID,
      lot_number: "LOT-001",
      manufacture_date: "2026-07-01",
      expiry_date: "2027-07-01",
      status: "active",
      hold_reason: null,
      parent_lot_id: null,
      source_type: "receipt",
      source_id: null,
      record_version: 1,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(lot.lotNumber, "LOT-001");
    assert.equal(lot.status, "active");
    assert.equal(lot.parentLotId, null);
  });
});

describe("parseSerialIdentity", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const serial = parseSerialIdentity({
      id: SERIAL_ID,
      tenant_id: TENANT_ID,
      owner_account_id: OWNER_ID,
      item_master_id: ITEM_ID,
      serial_number: "SN-001",
      lot_number: null,
      manufacture_date: null,
      expiry_date: null,
      status: "held",
      hold_reason: "hold_on_unknown_lot_policy_default",
      source_type: "receipt",
      source_id: null,
      idempotency_key: "idem-serial-1",
      record_version: 1,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(serial.serialNumber, "SN-001");
    assert.equal(serial.status, "held");
    assert.equal(serial.holdReason, "hold_on_unknown_lot_policy_default");
  });
});

describe("parseTraceEvent", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const event = parseTraceEvent({
      movement_id: MOVEMENT_ID,
      movement_type: "receipt",
      source_type: "wms_inbound_order",
      source_id: null,
      occurred_at: "2026-08-03T00:00:00.000Z",
      warehouse_id: WAREHOUSE_ID,
      location_id: LOCATION_ID,
      signed_quantity: "10",
      line_status: "on_hand",
    });
    assert.equal(event.movementType, "receipt");
    assert.equal(event.signedQuantity, 10);
  });
});

describe("parseAllocationCandidate", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const candidate = parseAllocationCandidate({
      balance_id: BALANCE_ID,
      location_id: LOCATION_ID,
      lot_number: "LOT-001",
      serial_number: null,
      manufacture_date: "2026-07-01",
      expiry_date: "2026-08-10",
      available: "5",
      lot_status: "active",
      serial_status: null,
      near_expiry: true,
    });
    assert.equal(candidate.available, 5);
    assert.equal(candidate.nearExpiry, true);
    assert.equal(candidate.lotStatus, "active");
  });
});

describe("CreateItemControlPolicyVersionDraftInputSchema", () => {
  test("accepts null allocationRule/holdOnUnknownLot/nearExpiryWarningDays/effectiveFrom", () => {
    const parsed = CreateItemControlPolicyVersionDraftInputSchema.parse({
      itemMasterId: ITEM_ID,
      allocationRule: null,
      holdOnUnknownLot: null,
      nearExpiryWarningDays: null,
      effectiveFrom: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.allocationRule, null);
  });

  test("rejects a negative nearExpiryWarningDays", () => {
    assert.throws(() =>
      CreateItemControlPolicyVersionDraftInputSchema.parse({
        itemMasterId: ITEM_ID,
        allocationRule: "fefo",
        holdOnUnknownLot: true,
        nearExpiryWarningDays: -1,
        effectiveFrom: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("RegisterLotIdentityInputSchema", () => {
  test("rejects an empty lotNumber", () => {
    assert.throws(() =>
      RegisterLotIdentityInputSchema.parse({
        itemMasterId: ITEM_ID,
        lotNumber: "",
        manufactureDate: null,
        expiryDate: null,
        sourceType: null,
        sourceId: null,
        parentLotId: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("accepts a real registration payload with a parentLotId (split genealogy)", () => {
    const parsed = RegisterLotIdentityInputSchema.parse({
      itemMasterId: ITEM_ID,
      lotNumber: "LOT-CHILD-1",
      manufactureDate: "2026-07-01",
      expiryDate: "2027-07-01",
      sourceType: "split",
      sourceId: null,
      parentLotId: LOT_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.parentLotId, LOT_ID);
  });
});

describe("RegisterSerialIdentityInputSchema", () => {
  test("rejects an empty idempotencyKey", () => {
    assert.throws(() =>
      RegisterSerialIdentityInputSchema.parse({
        itemMasterId: ITEM_ID,
        serialNumber: "SN-001",
        lotNumber: null,
        manufactureDate: null,
        expiryDate: null,
        sourceType: null,
        sourceId: null,
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("SetLotIdentityStatusInputSchema", () => {
  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      SetLotIdentityStatusInputSchema.parse({
        lotIdentityId: LOT_ID,
        newStatus: "shipped",
        reason: "not real",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supervisor",
      }),
    );
  });

  test("accepts a null reason (only enforced server-side for a non-active target status)", () => {
    const parsed = SetLotIdentityStatusInputSchema.parse({
      lotIdentityId: LOT_ID,
      newStatus: "active",
      reason: null,
      expectedVersion: 2,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(parsed.reason, null);
  });
});
