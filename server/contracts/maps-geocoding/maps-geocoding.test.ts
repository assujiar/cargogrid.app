import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseGeocodeRequest, parseMapsProviderDispatchInfo, RecordGeocodeRequestInputSchema } from "./maps-geocoding.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseGeocodeRequest", () => {
  test("maps snake_case columns to camelCase, including real metered cost", () => {
    const request = parseGeocodeRequest({
      id: REQUEST_ID,
      tenant_id: TENANT_ID,
      connection_id: CONNECTION_ID,
      request_type: "geocode",
      query_payload: { address: "123 Main St" },
      status: "success",
      result_payload: { lat: 1.23, lng: 4.56 },
      provider_unit_cost_amount: 0.01,
      currency: "USD",
      billed_amount: 0.012,
      error_message: null,
      requested_by_auth_user_id: ACTOR_ID,
      requested_by: "tenant admin",
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(request.requestType, "geocode");
    assert.equal(request.billedAmount, 0.012);
  });

  test("a failed request carries null result/cost fields, not a crash", () => {
    const request = parseGeocodeRequest({
      id: REQUEST_ID,
      tenant_id: TENANT_ID,
      connection_id: CONNECTION_ID,
      request_type: "route",
      query_payload: { origin: "A", destination: "B" },
      status: "failed",
      result_payload: null,
      provider_unit_cost_amount: null,
      currency: null,
      billed_amount: null,
      error_message: "provider timeout",
      requested_by_auth_user_id: ACTOR_ID,
      requested_by: "tenant admin",
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(request.billedAmount, null);
    assert.equal(request.errorMessage, "provider timeout");
  });
});

describe("parseMapsProviderDispatchInfo", () => {
  test("maps snake_case columns to camelCase", () => {
    const info = parseMapsProviderDispatchInfo({ connection_id: CONNECTION_ID, connection_status: "active", connection_config: { apiUrl: "https://maps.example.test/geocode" } });
    assert.equal(info.connectionStatus, "active");
    assert.equal(info.connectionConfig.apiUrl, "https://maps.example.test/geocode");
  });
});

describe("RecordGeocodeRequestInputSchema", () => {
  test("defaults optional fields to null", () => {
    const parsed = RecordGeocodeRequestInputSchema.parse({
      tenantId: TENANT_ID,
      connectionId: CONNECTION_ID,
      requestType: "geocode",
      queryPayload: { address: "123 Main St" },
      status: "success",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "system",
    });
    assert.equal(parsed.resultPayload, null);
    assert.equal(parsed.providerUnitCostAmount, null);
  });

  test("rejects a negative cost", () => {
    assert.throws(() =>
      RecordGeocodeRequestInputSchema.parse({
        tenantId: TENANT_ID,
        connectionId: CONNECTION_ID,
        requestType: "geocode",
        queryPayload: { address: "123 Main St" },
        status: "success",
        providerUnitCostAmount: -1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "system",
      }),
    );
  });
});
