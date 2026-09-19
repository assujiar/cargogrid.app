import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listDispatchBoard, DispatchBoardQueryError, type DispatchBoardQueryClient } from "./dispatch-board.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

/**
 * CG-AUDIT-2026-09-02 O1 cluster 3 batch 1: listDispatchBoard issues two separate RPC
 * calls -- count_dispatch_board_shipment_orders (a bare scalar) and list_dispatch_board
 * (a row set), mirroring listDispatchReadyQueue's own count/data split. This mock routes
 * by function name.
 */
function fakeClient(
  countResponse: { data: unknown; error: { message: string } | null },
  dataResponse: { data: unknown; error: { message: string } | null },
  captureArgs?: (fn: string, args: Record<string, unknown>) => void,
): DispatchBoardQueryClient {
  return {
    rpc: (fn: string, args: Record<string, unknown>) => {
      captureArgs?.(fn, args);
      return Promise.resolve(fn === "count_dispatch_board_shipment_orders" ? countResponse : dataResponse);
    },
  } as unknown as DispatchBoardQueryClient;
}

const ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  idempotency_key: "idem-1",
  status: "assigned",
  shipper_account_id: ACCOUNT_ID,
  consignee_snapshot: {},
  notify_party_snapshot: null,
  cargo_service_snapshot: {},
  service_type: "land_freight",
  mode: "land",
  origin: "Jakarta",
  destination: "Bandung",
  planned_pickup_at: null,
  planned_delivery_at: null,
  basis_quantity: null,
  basis_weight_kg: null,
  basis_volume_cbm: null,
  allocated_quantity: null,
  allocated_weight_kg: null,
  allocated_volume_cbm: null,
  split_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-29T00:00:00.000Z",
  updated_at: "2026-07-29T00:00:00.000Z",
  leg_network_status: null,
  is_ready: true,
  blockers: [],
  has_active_assignment: true,
  tracking_status: "not_tracked",
  authoritative_source_type: null,
  last_position_at: null,
  freshness_status: "unknown",
  accuracy_meters: null,
  fallback_active: false,
  tracking_entitled: false,
  tracking_exception_count: 0,
};

describe("listDispatchBoard", () => {
  test("maps rows and pagination metadata", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeClient({ data: 1, error: null }, { data: [ROW], error: null }, (fn, args) => calls.push({ fn, args }));
    const result = await listDispatchBoard(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 });
    assert.equal(result.rows.length, 1);
    assert.equal(result.totalCount, 1);
    assert.equal(result.rows[0]?.trackingStatus, "not_tracked");
    const listCall = calls.find((c) => c.fn === "list_dispatch_board");
    assert.equal(listCall?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(listCall?.args.p_tenant_id, TENANT_ID);
  });

  test("surfaces a count RPC error as DispatchBoardQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } }, { data: [], error: null });
    await assert.rejects(() => listDispatchBoard(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 }), DispatchBoardQueryError);
  });

  test("surfaces a data RPC error as DispatchBoardQueryError", async () => {
    const client = fakeClient({ data: 0, error: null }, { data: null, error: { message: "connection reset" } });
    await assert.rejects(() => listDispatchBoard(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 }), DispatchBoardQueryError);
  });
});
