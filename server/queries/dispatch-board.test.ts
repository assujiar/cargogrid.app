import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listDispatchBoard, DispatchBoardQueryError, type DispatchBoardQueryClient } from "./dispatch-board.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null; count: number | null }): DispatchBoardQueryClient {
  return {
    from() {
      return {
        select() {
          return this;
        },
        eq() {
          return this;
        },
        order() {
          return this;
        },
        range() {
          return Promise.resolve(response);
        },
      };
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
    const client = fakeClient({ data: [ROW], error: null, count: 1 });
    const result = await listDispatchBoard(client, { tenantId: TENANT_ID, page: 1 });
    assert.equal(result.rows.length, 1);
    assert.equal(result.totalCount, 1);
    assert.equal(result.rows[0]?.trackingStatus, "not_tracked");
  });

  test("surfaces a real query error as DispatchBoardQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" }, count: null });
    await assert.rejects(() => listDispatchBoard(client, { tenantId: TENANT_ID, page: 1 }), DispatchBoardQueryError);
  });
});
