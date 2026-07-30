import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseDispatchBoardRow } from "./dispatch-board.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const BASE_ROW = {
  id: SHIPMENT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  shipment_number: "SHP-2026-000001",
  idempotency_key: "idem-1",
  status: "assigned",
  shipper_account_id: ACCOUNT_ID,
  consignee_snapshot: { legal_name: "Acme Board Co" },
  notify_party_snapshot: null,
  cargo_service_snapshot: { service_type: "land_freight" },
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
};

describe("parseDispatchBoardRow", () => {
  test("maps an assigned row with readiness and honest untracked projection", () => {
    const row = parseDispatchBoardRow({
      ...BASE_ROW,
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
    });
    assert.equal(row.isReady, true);
    assert.equal(row.trackingStatus, "not_tracked");
    assert.equal(row.trackingEntitled, false);
  });

  test("maps a dispatched row with null readiness (meaningless once past assigned)", () => {
    const row = parseDispatchBoardRow({
      ...BASE_ROW,
      status: "dispatched",
      is_ready: null,
      blockers: null,
      has_active_assignment: true,
      tracking_status: "not_tracked",
      authoritative_source_type: null,
      last_position_at: null,
      freshness_status: "unknown",
      accuracy_meters: null,
      fallback_active: false,
      tracking_entitled: false,
      tracking_exception_count: 0,
    });
    assert.equal(row.isReady, null);
    assert.equal(row.blockers, null);
  });

  test("maps a real tracking-health row honestly (not silently defaulted once one exists)", () => {
    const row = parseDispatchBoardRow({
      ...BASE_ROW,
      status: "in_transit",
      is_ready: null,
      blockers: null,
      has_active_assignment: true,
      tracking_status: "stale",
      authoritative_source_type: "driver_mobile",
      last_position_at: "2026-07-29T10:00:00.000Z",
      freshness_status: "stale",
      accuracy_meters: 50,
      fallback_active: true,
      tracking_entitled: false,
      tracking_exception_count: 2,
    });
    assert.equal(row.trackingStatus, "stale");
    assert.equal(row.fallbackActive, true);
    assert.equal(row.trackingExceptionCount, 2);
  });
});
