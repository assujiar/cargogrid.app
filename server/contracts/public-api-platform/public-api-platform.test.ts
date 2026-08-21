import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseApiVersion,
  parseAuthenticateAndAuthorizeApiRequestResult,
  ApiVersionStatusSchema,
  ApiGatewayOutcomeSchema,
  ListApiLogsForTenantInputSchema,
} from "./public-api-platform.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const KEY_ID = "323e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseApiVersion", () => {
  test("maps snake_case columns to camelCase", () => {
    const version = parseApiVersion({
      code: "v1",
      status: "active",
      sunset_at: null,
      notes: "Initial public API version.",
      registered_by: "system",
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(version.code, "v1");
    assert.equal(version.sunsetAt, null);
    assert.equal(version.registeredBy, "system");
  });

  test("carries a real sunset_at for a sunset version", () => {
    const version = parseApiVersion({
      code: "v0",
      status: "sunset",
      sunset_at: "2026-12-01T00:00:00.000Z",
      notes: null,
      registered_by: "supreme",
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(version.status, "sunset");
    assert.equal(version.sunsetAt, "2026-12-01T00:00:00.000Z");
  });
});

describe("ApiVersionStatusSchema", () => {
  test("accepts active/deprecated/sunset", () => {
    for (const status of ["active", "deprecated", "sunset"]) {
      assert.equal(ApiVersionStatusSchema.parse(status), status);
    }
  });

  test("rejects an unsupported status", () => {
    assert.throws(() => ApiVersionStatusSchema.parse("beta"));
  });
});

describe("ApiGatewayOutcomeSchema", () => {
  test("accepts every real gateway outcome", () => {
    for (const outcome of ["ok", "unauthenticated", "forbidden_scope", "rate_limited"]) {
      assert.equal(ApiGatewayOutcomeSchema.parse(outcome), outcome);
    }
  });
});

describe("parseAuthenticateAndAuthorizeApiRequestResult", () => {
  test("an ok outcome carries the real dispatch identity and rate-limit evidence", () => {
    const result = parseAuthenticateAndAuthorizeApiRequestResult({
      outcome: "ok",
      api_key_id: KEY_ID,
      tenant_id: TENANT_ID,
      created_by_auth_user_id: AUTH_USER_ID,
      rate_limit_per_minute: 60,
      rate_limit_remaining: 59,
    });
    assert.equal(result.outcome, "ok");
    assert.equal(result.createdByAuthUserId, AUTH_USER_ID);
    assert.equal(result.rateLimitRemaining, 59);
  });

  test("an unauthenticated outcome carries no identity at all", () => {
    const result = parseAuthenticateAndAuthorizeApiRequestResult({
      outcome: "unauthenticated",
      api_key_id: null,
      tenant_id: null,
      created_by_auth_user_id: null,
      rate_limit_per_minute: null,
      rate_limit_remaining: null,
    });
    assert.equal(result.outcome, "unauthenticated");
    assert.equal(result.apiKeyId, null);
  });

  test("a forbidden_scope outcome resolves the key/tenant but never a downstream dispatch identity", () => {
    const result = parseAuthenticateAndAuthorizeApiRequestResult({
      outcome: "forbidden_scope",
      api_key_id: KEY_ID,
      tenant_id: TENANT_ID,
      created_by_auth_user_id: null,
      rate_limit_per_minute: 60,
      rate_limit_remaining: null,
    });
    assert.equal(result.outcome, "forbidden_scope");
    assert.equal(result.apiKeyId, KEY_ID);
    assert.equal(result.createdByAuthUserId, null);
  });

  test("a rate_limited outcome reports zero remaining", () => {
    const result = parseAuthenticateAndAuthorizeApiRequestResult({
      outcome: "rate_limited",
      api_key_id: KEY_ID,
      tenant_id: TENANT_ID,
      created_by_auth_user_id: null,
      rate_limit_per_minute: 60,
      rate_limit_remaining: 0,
    });
    assert.equal(result.outcome, "rate_limited");
    assert.equal(result.rateLimitRemaining, 0);
  });
});

describe("ListApiLogsForTenantInputSchema", () => {
  test("defaults limit to 20 and before to null", () => {
    const parsed = ListApiLogsForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: AUTH_USER_ID });
    assert.equal(parsed.limit, 20);
    assert.equal(parsed.before, null);
  });

  test("rejects a limit above 100", () => {
    assert.throws(() => ListApiLogsForTenantInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: AUTH_USER_ID, limit: 101 }));
  });
});
