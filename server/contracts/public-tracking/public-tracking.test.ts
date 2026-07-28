import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseIssuedShipmentTrackingToken, parseShipmentTrackingToken, parsePublicShipmentTrackingResult } from "./public-tracking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const TOKEN_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseIssuedShipmentTrackingToken", () => {
  test("maps the one-time issuance result", () => {
    const issued = parseIssuedShipmentTrackingToken({
      token_id: TOKEN_ID,
      raw_token: "a".repeat(64),
      expires_at: "2026-08-27T09:00:00.000Z",
      shipment_order_id: SHIPMENT_ID,
    });
    assert.equal(issued.tokenId, TOKEN_ID);
    assert.equal(issued.rawToken.length, 64);
  });
});

describe("parseShipmentTrackingToken", () => {
  test("maps an active token", () => {
    const token = parseShipmentTrackingToken({
      id: TOKEN_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      status: "active",
      expires_at: "2026-08-27T09:00:00.000Z",
      revoked_at: null,
      revoked_reason: null,
      created_by: "rep",
      created_at: "2026-07-28T09:00:00.000Z",
    });
    assert.equal(token.status, "active");
    assert.equal(token.revokedAt, null);
  });

  test("maps a revoked token", () => {
    const token = parseShipmentTrackingToken({
      id: TOKEN_ID,
      tenant_id: TENANT_ID,
      shipment_order_id: SHIPMENT_ID,
      status: "revoked",
      expires_at: "2026-08-27T09:00:00.000Z",
      revoked_at: "2026-07-28T10:00:00.000Z",
      revoked_reason: "superseded_by_new_issuance",
      created_by: "rep",
      created_at: "2026-07-28T09:00:00.000Z",
    });
    assert.equal(token.status, "revoked");
    assert.equal(token.revokedReason, "superseded_by_new_issuance");
  });
});

describe("parsePublicShipmentTrackingResult", () => {
  test("maps a successful lookup with a sanitized, customer-visible-only milestone timeline", () => {
    const result = parsePublicShipmentTrackingResult({
      lookup_status: "ok",
      shipment_number: "SHP-0001",
      status: "in_transit",
      mode: "sea",
      origin: "Jakarta",
      destination: "Surabaya",
      planned_delivery_at: "2026-08-05T00:00:00.000Z",
      current_eta: null,
      is_delayed: false,
      milestones: [{ code: "picked_up", eventTime: "2026-07-27T09:00:00.000Z" }],
      epod_available: false,
    });
    assert.equal(result.lookupStatus, "ok");
    assert.equal(result.milestones.length, 1);
    assert.equal(result.milestones[0]?.code, "picked_up");
  });

  test("maps a not_found outcome with every other field null", () => {
    const result = parsePublicShipmentTrackingResult({
      lookup_status: "not_found",
      shipment_number: null,
      status: null,
      mode: null,
      origin: null,
      destination: null,
      planned_delivery_at: null,
      current_eta: null,
      is_delayed: null,
      milestones: [],
      epod_available: null,
    });
    assert.equal(result.lookupStatus, "not_found");
    assert.equal(result.shipmentNumber, null);
    assert.deepEqual(result.milestones, []);
  });

  test("maps a rate_limited outcome", () => {
    const result = parsePublicShipmentTrackingResult({
      lookup_status: "rate_limited",
      shipment_number: null,
      status: null,
      mode: null,
      origin: null,
      destination: null,
      planned_delivery_at: null,
      current_eta: null,
      is_delayed: null,
      milestones: [],
      epod_available: null,
    });
    assert.equal(result.lookupStatus, "rate_limited");
  });
});
