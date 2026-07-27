import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { formatCompactNumber, formatCurrency, formatCount, formatPercent, formatDuration } from "./chart-formatters.ts";

describe("formatCompactNumber", () => {
  test("formats billions as miliar", () => {
    assert.equal(formatCompactNumber(4_820_000_000), "4,8 miliar");
  });
  test("formats millions as juta", () => {
    assert.equal(formatCompactNumber(850_000_000), "850 juta");
  });
  test("formats thousands as ribu", () => {
    assert.equal(formatCompactNumber(1_500), "1,5 ribu");
  });
  test("leaves small numbers grouped, no suffix", () => {
    assert.equal(formatCompactNumber(925), "925");
  });
  test("handles zero", () => {
    assert.equal(formatCompactNumber(0), "0");
  });
});

describe("formatCurrency", () => {
  test("IDR compact by default", () => {
    assert.equal(formatCurrency(4_820_000_000, "IDR"), "Rp4,8 miliar");
  });
  test("IDR non-compact", () => {
    assert.equal(formatCurrency(4_820_000_000, "IDR", { compact: false }), "Rp4.820.000.000");
  });
  test("non-IDR currency is never auto-converted, code prefixed instead of a symbol", () => {
    assert.equal(formatCurrency(48_200, "USD"), "USD 48.200");
  });
});

describe("formatCount", () => {
  test("groups with the id-ID thousands separator", () => {
    assert.equal(formatCount(1250, "shipment"), "1.250 shipment");
  });
});

describe("formatPercent", () => {
  test("default one decimal, comma separator", () => {
    assert.equal(formatPercent(18.5), "18,5%");
  });
  test("signed shows a leading +", () => {
    assert.equal(formatPercent(8.4, { signed: true }), "+8,4%");
  });
  test("signed shows a leading - for negative values", () => {
    assert.equal(formatPercent(-3.2, { signed: true }), "-3,2%");
  });
});

describe("formatDuration", () => {
  test("hari unit", () => {
    assert.equal(formatDuration(7, "hari"), "7 hari");
  });
  test("jam unit", () => {
    assert.equal(formatDuration(24, "jam"), "24 jam");
  });
});
