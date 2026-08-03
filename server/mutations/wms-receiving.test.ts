import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  startWmsReceiptSession,
  recordWmsReceiptLineCount,
  approveWmsReceiptOverage,
  commitWmsReceiptLine,
  completeWmsReceiptSession,
  cancelWmsReceiptSession,
  resolveWmsReceiptHold,
  WmsReceivingMutationError,
  type WmsReceivingMutationRpcClient,
} from "./wms-receiving.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const INBOUND_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const SESSION_ID = "623e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "723e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "823e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "923e4567-e89b-12d3-a456-426614174000";
const INBOUND_LINE_ID = "a23e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "b23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsReceivingMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsReceivingMutationRpcClient;
  return { client, calls };
}

const SESSION_ROW = {
  id: SESSION_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  inbound_order_id: INBOUND_ORDER_ID,
  receiving_location_id: LOCATION_ID,
  idempotency_key: "idem-1",
  status: "in_progress",
  cancelled_reason: null,
  started_by: "rep",
  started_at: "2026-08-03T00:00:00.000Z",
  completed_at: null,
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const LINE_ROW = {
  id: LINE_ID,
  tenant_id: TENANT_ID,
  receipt_session_id: SESSION_ID,
  inbound_order_line_id: INBOUND_LINE_ID,
  line_number: 1,
  item_master_id: ITEM_ID,
  owner_account_id: OWNER_ID,
  expected_uom_code: "PCS",
  expected_quantity: "10",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  counted_uom_code: "PCS",
  counted_quantity: "10",
  accepted_quantity: "10",
  damaged_quantity: "0",
  held_quantity: "0",
  rejected_quantity: "0",
  over_quantity: "0",
  short_quantity: "0",
  lot_number: null,
  serial_number: null,
  expiry_date: null,
  condition_notes: null,
  status: "counted",
  over_approved: false,
  over_approved_reason: null,
  over_approved_by: null,
  over_approved_at: null,
  hold_resolved: false,
  hold_resolution: null,
  hold_resolved_reason: null,
  hold_resolved_by: null,
  hold_resolved_at: null,
  resolution_movement_id: null,
  movement_id: null,
  record_version: 2,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("startWmsReceiptSession", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [SESSION_ROW], error: null });
    const session = await startWmsReceiptSession(client, {
      inboundOrderId: INBOUND_ORDER_ID,
      receivingLocationId: LOCATION_ID,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(session.inboundOrderId, INBOUND_ORDER_ID);
    assert.equal(calls[0]?.fn, "start_wms_receipt_session");
  });

  test("classifies inbound_not_confirmed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "inbound_not_confirmed: x must be confirmed to start receiving, is draft" } });
    await assert.rejects(
      () =>
        startWmsReceiptSession(client, {
          inboundOrderId: INBOUND_ORDER_ID,
          receivingLocationId: LOCATION_ID,
          idempotencyKey: "idem-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsReceivingMutationError && err.code === "inbound_not_confirmed",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        startWmsReceiptSession(client, {
          inboundOrderId: INBOUND_ORDER_ID,
          receivingLocationId: LOCATION_ID,
          idempotencyKey: "idem-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsReceivingMutationError && err.code === "mutation_failed",
    );
  });
});

describe("recordWmsReceiptLineCount", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [LINE_ROW], error: null });
    const line = await recordWmsReceiptLineCount(client, {
      lineId: LINE_ID,
      uomCode: null,
      countedQuantity: 10,
      acceptedQuantity: 10,
      damagedQuantity: 0,
      heldQuantity: 0,
      rejectedQuantity: 0,
      lotNumber: null,
      serialNumber: null,
      expiryDate: null,
      conditionNotes: null,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(line.status, "counted");
    assert.equal(calls[0]?.fn, "record_wms_receipt_line_count");
    assert.equal(calls[0]?.args.p_counted_quantity, 10);
  });

  test("classifies invalid_equation", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_equation: accepted (5) + damaged (0) + held (0) + rejected (0) must equal counted (10)" } });
    await assert.rejects(
      () =>
        recordWmsReceiptLineCount(client, {
          lineId: LINE_ID,
          uomCode: null,
          countedQuantity: 10,
          acceptedQuantity: 5,
          damagedQuantity: 0,
          heldQuantity: 0,
          rejectedQuantity: 0,
          lotNumber: null,
          serialNumber: null,
          expiryDate: null,
          conditionNotes: null,
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsReceivingMutationError && err.code === "invalid_equation",
    );
  });
});

describe("approveWmsReceiptOverage", () => {
  test("classifies no_overage_to_approve", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "no_overage_to_approve: receipt line x has no overage (over_quantity=0)" } });
    await assert.rejects(
      () => approveWmsReceiptOverage(client, { lineId: LINE_ID, reason: "customer approved extra pallet", expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => err instanceof WmsReceivingMutationError && err.code === "no_overage_to_approve",
    );
  });
});

describe("commitWmsReceiptLine", () => {
  test("classifies unapproved_overage", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "unapproved_overage: receipt line x counted 5 over the expected 10 without supervisor approval" } });
    await assert.rejects(
      () => commitWmsReceiptLine(client, { lineId: LINE_ID, idempotencyKey: "idem-commit-1", expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsReceivingMutationError && err.code === "unapproved_overage",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...LINE_ROW, status: "committed", movement_id: "c23e4567-e89b-12d3-a456-426614174000" }], error: null });
    const line = await commitWmsReceiptLine(client, { lineId: LINE_ID, idempotencyKey: "idem-commit-1", expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(line.status, "committed");
    assert.equal(calls[0]?.fn, "commit_wms_receipt_line");
  });
});

describe("completeWmsReceiptSession", () => {
  test("classifies lines_not_committed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "lines_not_committed: 2 line(s) on session x are not yet committed" } });
    await assert.rejects(
      () => completeWmsReceiptSession(client, { sessionId: SESSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsReceivingMutationError && err.code === "lines_not_committed",
    );
  });
});

describe("cancelWmsReceiptSession", () => {
  test("classifies has_committed_lines", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "has_committed_lines: session x has 1 already-committed line(s) -- complete the session instead" } });
    await assert.rejects(
      () => cancelWmsReceiptSession(client, { sessionId: SESSION_ID, reason: "wrong appointment", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsReceivingMutationError && err.code === "has_committed_lines",
    );
  });

  test("sends a null reason through unchanged (no-op path)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SESSION_ROW, status: "cancelled", cancelled_reason: "x" }], error: null });
    const session = await cancelWmsReceiptSession(client, { sessionId: SESSION_ID, reason: null, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(session.status, "cancelled");
    assert.equal(calls[0]?.args.p_reason, null);
  });
});

describe("resolveWmsReceiptHold", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ ...LINE_ROW, held_quantity: "0", hold_resolved: true, hold_resolution: "release_to_stock" }],
      error: null,
    });
    const line = await resolveWmsReceiptHold(client, {
      lineId: LINE_ID,
      resolution: "release_to_stock",
      reason: "QC passed on inspection",
      idempotencyKey: "idem-hold-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(line.holdResolved, true);
    assert.equal(calls[0]?.fn, "resolve_wms_receipt_hold");
    assert.equal(calls[0]?.args.p_resolution, "release_to_stock");
  });

  test("classifies no_held_quantity", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "no_held_quantity: receipt line x has no held quantity to resolve" } });
    await assert.rejects(
      () =>
        resolveWmsReceiptHold(client, {
          lineId: LINE_ID,
          resolution: "confirm_damaged",
          reason: "inspection failed",
          idempotencyKey: "idem-hold-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof WmsReceivingMutationError && err.code === "no_held_quantity",
    );
  });
});
