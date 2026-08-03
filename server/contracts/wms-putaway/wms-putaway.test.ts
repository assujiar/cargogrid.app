import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWmsPutawayTask,
  parseWmsPutawayConfirmation,
  GenerateWmsPutawayTaskInputSchema,
  ConfirmWmsPutawayTaskInputSchema,
  ReassignWmsPutawayTaskInputSchema,
} from "./wms-putaway.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const RECEIPT_LINE_ID = "423e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const TASK_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const CONFIRMATION_ID = "a23e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "b23e4567-e89b-12d3-a456-426614174000";

const TASK_ROW = {
  id: TASK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  receipt_line_id: RECEIPT_LINE_ID,
  source_location_id: LOCATION_ID,
  item_master_id: ITEM_ID,
  owner_account_id: OWNER_ID,
  uom_code: "PCS",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  lot_number: null,
  serial_number: null,
  expiry_date: null,
  task_quantity: "50",
  confirmed_quantity: "0",
  remaining_quantity: "50",
  suggested_location_id: LOCATION_ID,
  suggested_reason: "auto_suggested_first_eligible_capacity_headroom",
  actual_location_id: null,
  status: "unclaimed",
  claimed_by_auth_user_id: null,
  claimed_by_label: null,
  claimed_at: null,
  exception_reason: null,
  idempotency_key: "idem-task-1",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("parseWmsPutawayTask", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const task = parseWmsPutawayTask(TASK_ROW);
    assert.equal(task.id, TASK_ID);
    assert.equal(task.taskQuantity, 50);
    assert.equal(task.remainingQuantity, 50);
    assert.equal(task.status, "unclaimed");
    assert.equal(task.claimedByAuthUserId, null);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => parseWmsPutawayTask({ ...TASK_ROW, status: "bogus" }));
  });
});

describe("parseWmsPutawayConfirmation", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const confirmation = parseWmsPutawayConfirmation({
      id: CONFIRMATION_ID,
      tenant_id: TENANT_ID,
      task_id: TASK_ID,
      idempotency_key: "idem-confirm-1",
      quantity: "20",
      actual_location_id: LOCATION_ID,
      movement_id: MOVEMENT_ID,
      lot_number: null,
      serial_number: null,
      expiry_date: null,
      confirmed_by_auth_user_id: ACTOR_ID,
      confirmed_by_label: "picker",
      confirmed_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(confirmation.quantity, 20);
    assert.equal(confirmation.movementId, MOVEMENT_ID);
  });
});

describe("GenerateWmsPutawayTaskInputSchema", () => {
  test("accepts a null suggestedLocationId (auto-suggest)", () => {
    const parsed = GenerateWmsPutawayTaskInputSchema.parse({
      receiptLineId: RECEIPT_LINE_ID,
      quantity: 10,
      suggestedLocationId: null,
      idempotencyKey: "idem-gen-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.suggestedLocationId, null);
  });

  test("rejects a non-positive quantity", () => {
    assert.throws(() =>
      GenerateWmsPutawayTaskInputSchema.parse({
        receiptLineId: RECEIPT_LINE_ID,
        quantity: 0,
        suggestedLocationId: null,
        idempotencyKey: "idem-gen-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("ConfirmWmsPutawayTaskInputSchema", () => {
  test("accepts null lot/serial numbers", () => {
    const parsed = ConfirmWmsPutawayTaskInputSchema.parse({
      taskId: TASK_ID,
      quantity: 10,
      actualLocationId: LOCATION_ID,
      lotNumber: null,
      serialNumber: null,
      idempotencyKey: "idem-confirm-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "picker",
    });
    assert.equal(parsed.lotNumber, null);
  });
});

describe("ReassignWmsPutawayTaskInputSchema", () => {
  test("accepts a null newClaimantAuthUserId (release)", () => {
    const parsed = ReassignWmsPutawayTaskInputSchema.parse({
      taskId: TASK_ID,
      newClaimantAuthUserId: null,
      newClaimantLabel: null,
      reason: "staff went home sick",
      expectedVersion: 2,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(parsed.newClaimantAuthUserId, null);
  });

  test("rejects an empty reason", () => {
    assert.throws(() =>
      ReassignWmsPutawayTaskInputSchema.parse({
        taskId: TASK_ID,
        newClaimantAuthUserId: null,
        newClaimantLabel: null,
        reason: "",
        expectedVersion: 2,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supervisor",
      }),
    );
  });
});
