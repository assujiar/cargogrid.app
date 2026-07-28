import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseShipmentStatusEntry,
  parseMilestoneSlaEntry,
  parseExceptionQueueEntry,
  parseEpodCompletionEntry,
  parseCostVarianceEntry,
  parseBillingReadinessSummaryEntry,
} from "./ops-dashboard.ts";

describe("parseShipmentStatusEntry", () => {
  test("maps a row", () => {
    const entry = parseShipmentStatusEntry({ status: "delivered", shipment_count: "3" });
    assert.equal(entry.status, "delivered");
    assert.equal(entry.shipmentCount, 3);
  });
});

describe("parseMilestoneSlaEntry", () => {
  test("maps a row", () => {
    const entry = parseMilestoneSlaEntry({ bucket: "delayed", shipment_count: "1" });
    assert.equal(entry.bucket, "delayed");
    assert.equal(entry.shipmentCount, 1);
  });
});

describe("parseExceptionQueueEntry", () => {
  test("maps a row", () => {
    const entry = parseExceptionQueueEntry({ severity: "high", exception_count: "1" });
    assert.equal(entry.severity, "high");
    assert.equal(entry.exceptionCount, 1);
  });
});

describe("parseEpodCompletionEntry", () => {
  test("maps a row", () => {
    const entry = parseEpodCompletionEntry({ status: "completed", capture_count: "1" });
    assert.equal(entry.status, "completed");
    assert.equal(entry.captureCount, 1);
  });
});

describe("parseCostVarianceEntry", () => {
  test("maps an unmasked row", () => {
    const entry = parseCostVarianceEntry({ bucket: "over_budget", currency: "IDR", shipment_count: "1", avg_variance_pct: "30.00", variance_masked: false });
    assert.equal(entry.bucket, "over_budget");
    assert.equal(entry.avgVariancePct, 30);
    assert.equal(entry.varianceMasked, false);
  });

  test("maps a masked row -- avgVariancePct null, varianceMasked true, never a fabricated zero", () => {
    const entry = parseCostVarianceEntry({ bucket: "under_budget", currency: "IDR", shipment_count: "1", avg_variance_pct: null, variance_masked: true });
    assert.equal(entry.avgVariancePct, null);
    assert.equal(entry.varianceMasked, true);
  });
});

describe("parseBillingReadinessSummaryEntry", () => {
  test("maps a row", () => {
    const entry = parseBillingReadinessSummaryEntry({ bucket: "not_ready", job_count: "1" });
    assert.equal(entry.bucket, "not_ready");
    assert.equal(entry.jobCount, 1);
  });
});
