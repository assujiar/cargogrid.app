import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseShipmentActualCost, parseShipmentActualCostDirectoryRow, parseShipmentActualCostComponent, parseActualCostVariance } from "./actual-cost.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const COST_ID = "423e4567-e89b-12d3-a456-426614174000";
const COMPONENT_ID = "523e4567-e89b-12d3-a456-426614174000";

const BASE_COST_ROW = {
  id: COST_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  version_number: 1,
  is_current: true,
  supersedes_version_id: null,
  status: "draft",
  currency: "IDR",
  estimated_amount: null,
  total_amount: 0,
  approved_by_auth_user_id: null,
  approved_at: null,
  rejection_reason: null,
  adjustment_reason: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("parseShipmentActualCost", () => {
  test("maps a fresh draft with zero total", () => {
    const cost = parseShipmentActualCost(BASE_COST_ROW);
    assert.equal(cost.status, "draft");
    assert.equal(cost.totalAmount, 0);
    assert.equal(cost.estimatedAmount, null);
  });

  test("maps an approved cost with a real variance-eligible estimated_amount", () => {
    const cost = parseShipmentActualCost({ ...BASE_COST_ROW, status: "approved", estimated_amount: 12000000, total_amount: 10250000, approved_by_auth_user_id: TENANT_ID, approved_at: "2026-07-28T10:00:00.000Z" });
    assert.equal(cost.status, "approved");
    assert.equal(cost.estimatedAmount, 12000000);
    assert.equal(cost.totalAmount, 10250000);
  });
});

describe("parseShipmentActualCostDirectoryRow", () => {
  test("maps a masked row (no OPS:View cost)", () => {
    const row = parseShipmentActualCostDirectoryRow({ ...BASE_COST_ROW, estimated_amount: null, total_amount: null, cost_masked: true });
    assert.equal(row.costMasked, true);
    assert.equal(row.totalAmount, null);
  });

  test("maps an unmasked row (OPS:View cost granted)", () => {
    const row = parseShipmentActualCostDirectoryRow({ ...BASE_COST_ROW, total_amount: 10250000, cost_masked: false });
    assert.equal(row.costMasked, false);
    assert.equal(row.totalAmount, 10250000);
  });
});

describe("parseShipmentActualCostComponent", () => {
  test("maps a vendor-sourced component with a minimum charge and surcharge", () => {
    const component = parseShipmentActualCostComponent({
      id: COMPONENT_ID,
      tenant_id: TENANT_ID,
      actual_cost_id: COST_ID,
      category: "freight",
      source_type: "vendor",
      vendor_id: TENANT_ID,
      assignment_id: null,
      document_file_id: null,
      description: "Ocean freight",
      quantity: 1,
      uom: "shipment",
      rate: 9500000,
      minimum_charge: 10000000,
      surcharge: 250000,
      amount: 10250000,
      currency: "IDR",
      idempotency_key: "idem-1",
      created_by: "rep",
      created_at: "2026-07-28T09:00:00.000Z",
    });
    assert.equal(component.amount, 10250000);
    assert.equal(component.sourceType, "vendor");
  });
});

describe("parseActualCostVariance", () => {
  test("maps a real variance when estimated_amount was supplied", () => {
    const variance = parseActualCostVariance({ total_amount: 10250000, estimated_amount: 12000000, variance_amount: -1750000, variance_available: true });
    assert.equal(variance.varianceAvailable, true);
    assert.equal(variance.varianceAmount, -1750000);
  });

  test("maps variance_available=false when no estimate was ever supplied", () => {
    const variance = parseActualCostVariance({ total_amount: 10250000, estimated_amount: null, variance_amount: null, variance_available: false });
    assert.equal(variance.varianceAvailable, false);
    assert.equal(variance.varianceAmount, null);
  });
});
