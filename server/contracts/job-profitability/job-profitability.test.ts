import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseJobProfitabilitySnapshot, parseJobProfitabilityDirectoryRow } from "./job-profitability.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const SNAPSHOT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const BASE_ROW = {
  id: SNAPSHOT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  version_number: 1,
  is_current: true,
  status: "calculated",
  blocked_reason: null,
  revenue_basis: "quoted",
  revenue_currency: "IDR",
  revenue_amount: 15000000,
  cost_currency: "IDR",
  cost_amount: 8000000,
  margin_amount: 7000000,
  margin_percent: 46.6667,
  source_cost_version_ids: [SNAPSHOT_ID],
  recalculation_reason: null,
  calculated_by_auth_user_id: ACTOR_ID,
  calculated_at: "2026-07-28T09:00:00.000Z",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("parseJobProfitabilitySnapshot", () => {
  test("maps a calculated snapshot with a positive margin", () => {
    const snapshot = parseJobProfitabilitySnapshot(BASE_ROW);
    assert.equal(snapshot.status, "calculated");
    assert.equal(snapshot.marginAmount, 7000000);
    assert.equal(snapshot.marginPercent, 46.6667);
    assert.equal(snapshot.revenueBasis, "quoted");
  });

  test("maps an unavailable snapshot with null money fields", () => {
    const snapshot = parseJobProfitabilitySnapshot({
      ...BASE_ROW,
      status: "unavailable",
      blocked_reason: "mixed_currency",
      cost_currency: null,
      cost_amount: null,
      margin_amount: null,
      margin_percent: null,
    });
    assert.equal(snapshot.status, "unavailable");
    assert.equal(snapshot.blockedReason, "mixed_currency");
    assert.equal(snapshot.marginAmount, null);
    // ISS-2026-197: revenue_basis is metadata, not a computed figure -- never nulled out alongside a blocked calculation.
    assert.equal(snapshot.revenueBasis, "quoted");
  });
});

describe("parseJobProfitabilityDirectoryRow", () => {
  test("maps a masked row (no OPS:View margin)", () => {
    const row = parseJobProfitabilityDirectoryRow({ ...BASE_ROW, revenue_amount: null, cost_amount: null, margin_amount: null, margin_percent: null, source_cost_version_ids: [], margin_masked: true });
    assert.equal(row.marginMasked, true);
    assert.equal(row.marginAmount, null);
    assert.deepEqual(row.sourceCostVersionIds, []);
  });

  test("maps an unmasked row (OPS:View margin granted)", () => {
    const row = parseJobProfitabilityDirectoryRow({ ...BASE_ROW, margin_masked: false });
    assert.equal(row.marginMasked, false);
    assert.equal(row.marginAmount, 7000000);
  });
});
