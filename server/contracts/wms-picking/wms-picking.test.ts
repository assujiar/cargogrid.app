import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWmsPickTask,
  parseWmsPickTaskConfirmation,
  parseWmsPickTaskShort,
  parseWmsPickSubstitutionApproval,
  parseWmsPickWave,
  GenerateWmsPickTaskInputSchema,
  ConfirmWmsPickTaskInputSchema,
  RecordWmsPickTaskShortInputSchema,
  ReassignWmsPickTaskInputSchema,
  ApproveWmsPickSubstitutionInputSchema,
} from "./wms-picking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OUTBOUND_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const OUTBOUND_LINE_ID = "523e4567-e89b-12d3-a456-426614174000";
const TASK_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "a23e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "b23e4567-e89b-12d3-a456-426614174000";
const CONFIRMATION_ID = "c23e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "d23e4567-e89b-12d3-a456-426614174000";
const SHORT_ID = "e23e4567-e89b-12d3-a456-426614174000";
const APPROVAL_ID = "f23e4567-e89b-12d3-a456-426614174000";
const WAVE_ID = "023e4567-e89b-12d3-a456-426614174001";

const TASK_ROW = {
  id: TASK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  outbound_order_id: OUTBOUND_ORDER_ID,
  outbound_order_line_id: OUTBOUND_LINE_ID,
  wave_id: null,
  owner_account_id: OWNER_ID,
  item_master_id: ITEM_ID,
  uom_code: "PCS",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  source_location_id: LOCATION_ID,
  lot_number: null,
  serial_number: null,
  expiry_date: null,
  reservation_id: RESERVATION_ID,
  task_quantity: "50",
  picked_quantity: "0",
  short_quantity: "0",
  remaining_quantity: "50",
  suggested_destination_location_id: null,
  suggested_destination_reason: null,
  actual_destination_location_id: null,
  status: "unclaimed",
  claimed_by_auth_user_id: null,
  claimed_by_label: null,
  claimed_at: null,
  exception_reason: null,
  substituted_from_item_master_id: null,
  idempotency_key: "idem-task-1",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("parseWmsPickTask", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const task = parseWmsPickTask(TASK_ROW);
    assert.equal(task.id, TASK_ID);
    assert.equal(task.taskQuantity, 50);
    assert.equal(task.remainingQuantity, 50);
    assert.equal(task.status, "unclaimed");
    assert.equal(task.waveId, null);
    assert.equal(task.substitutedFromItemMasterId, null);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => parseWmsPickTask({ ...TASK_ROW, status: "bogus" }));
  });

  test("accepts every real status value, including short", () => {
    const task = parseWmsPickTask({ ...TASK_ROW, status: "short", short_quantity: "5" });
    assert.equal(task.status, "short");
    assert.equal(task.shortQuantity, 5);
  });
});

describe("parseWmsPickTaskConfirmation", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const confirmation = parseWmsPickTaskConfirmation({
      id: CONFIRMATION_ID,
      tenant_id: TENANT_ID,
      task_id: TASK_ID,
      idempotency_key: "idem-confirm-1",
      quantity: "20",
      scanned_location_id: LOCATION_ID,
      scanned_item_master_id: ITEM_ID,
      scanned_lot_number: null,
      scanned_serial_number: null,
      actual_destination_location_id: LOCATION_ID,
      movement_id: MOVEMENT_ID,
      confirmed_by_auth_user_id: ACTOR_ID,
      confirmed_by_label: "picker",
      confirmed_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(confirmation.quantity, 20);
    assert.equal(confirmation.movementId, MOVEMENT_ID);
  });
});

describe("parseWmsPickTaskShort", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const short = parseWmsPickTaskShort({
      id: SHORT_ID,
      tenant_id: TENANT_ID,
      task_id: TASK_ID,
      idempotency_key: "idem-short-1",
      quantity: "5",
      reason: "shelf empty",
      recorded_by_auth_user_id: ACTOR_ID,
      recorded_by_label: "picker",
      recorded_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(short.quantity, 5);
    assert.equal(short.reason, "shelf empty");
  });
});

describe("parseWmsPickSubstitutionApproval", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const approval = parseWmsPickSubstitutionApproval({
      id: APPROVAL_ID,
      tenant_id: TENANT_ID,
      task_id: TASK_ID,
      original_item_master_id: ITEM_ID,
      substitute_item_master_id: OWNER_ID,
      original_reservation_id: RESERVATION_ID,
      new_reservation_id: MOVEMENT_ID,
      reason: "supply shortage",
      idempotency_key: "idem-sub-1",
      approved_by_auth_user_id: ACTOR_ID,
      approved_by_label: "supervisor",
      approved_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(approval.reason, "supply shortage");
    assert.equal(approval.substituteItemMasterId, OWNER_ID);
  });
});

describe("parseWmsPickWave", () => {
  test("maps a snake_case row into the camelCase contract shape", () => {
    const wave = parseWmsPickWave({
      id: WAVE_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      wave_number: "WMSWAVE-2026-000001",
      idempotency_key: "idem-wave-1",
      created_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(wave.waveNumber, "WMSWAVE-2026-000001");
  });
});

describe("GenerateWmsPickTaskInputSchema", () => {
  test("accepts every field as null except the required ones", () => {
    const parsed = GenerateWmsPickTaskInputSchema.parse({
      outboundOrderLineId: OUTBOUND_LINE_ID,
      quantity: 10,
      waveId: null,
      locationId: null,
      lotNumber: null,
      serialNumber: null,
      suggestedDestinationLocationId: null,
      idempotencyKey: "idem-gen-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.locationId, null);
  });

  test("rejects a non-positive quantity", () => {
    assert.throws(() =>
      GenerateWmsPickTaskInputSchema.parse({
        outboundOrderLineId: OUTBOUND_LINE_ID,
        quantity: 0,
        waveId: null,
        locationId: null,
        lotNumber: null,
        serialNumber: null,
        suggestedDestinationLocationId: null,
        idempotencyKey: "idem-gen-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("ConfirmWmsPickTaskInputSchema", () => {
  test("accepts null lot/serial numbers", () => {
    const parsed = ConfirmWmsPickTaskInputSchema.parse({
      taskId: TASK_ID,
      quantity: 10,
      scannedLocationId: LOCATION_ID,
      scannedItemMasterId: ITEM_ID,
      scannedLotNumber: null,
      scannedSerialNumber: null,
      actualDestinationLocationId: LOCATION_ID,
      idempotencyKey: "idem-confirm-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "picker",
    });
    assert.equal(parsed.scannedLotNumber, null);
  });
});

describe("RecordWmsPickTaskShortInputSchema", () => {
  test("rejects an empty reason", () => {
    assert.throws(() =>
      RecordWmsPickTaskShortInputSchema.parse({
        taskId: TASK_ID,
        shortQuantity: 5,
        reason: "",
        idempotencyKey: "idem-short-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "picker",
      }),
    );
  });

  test("rejects a non-positive short quantity", () => {
    assert.throws(() =>
      RecordWmsPickTaskShortInputSchema.parse({
        taskId: TASK_ID,
        shortQuantity: 0,
        reason: "shelf empty",
        idempotencyKey: "idem-short-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "picker",
      }),
    );
  });
});

describe("ReassignWmsPickTaskInputSchema", () => {
  test("accepts a null newClaimantAuthUserId (release)", () => {
    const parsed = ReassignWmsPickTaskInputSchema.parse({
      taskId: TASK_ID,
      newClaimantAuthUserId: null,
      newClaimantLabel: null,
      reason: "picker went home sick",
      expectedVersion: 2,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(parsed.newClaimantAuthUserId, null);
  });
});

describe("ApproveWmsPickSubstitutionInputSchema", () => {
  test("accepts a null location/lot/serial (auto-select substitute source)", () => {
    const parsed = ApproveWmsPickSubstitutionInputSchema.parse({
      taskId: TASK_ID,
      substituteItemMasterId: OWNER_ID,
      locationId: null,
      lotNumber: null,
      serialNumber: null,
      reason: "supply shortage",
      idempotencyKey: "idem-sub-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(parsed.locationId, null);
  });

  test("rejects an empty reason", () => {
    assert.throws(() =>
      ApproveWmsPickSubstitutionInputSchema.parse({
        taskId: TASK_ID,
        substituteItemMasterId: OWNER_ID,
        locationId: null,
        lotNumber: null,
        serialNumber: null,
        reason: "",
        idempotencyKey: "idem-sub-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supervisor",
      }),
    );
  });
});
