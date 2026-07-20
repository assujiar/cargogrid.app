import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  buildApiError,
  paginatedResultSchema,
  CursorPaginationParamsSchema,
  OffsetPaginationParamsSchema,
  IdempotencyKeySchema,
  CorrelationIdSchema,
  parseApiLog,
  API_VERSION,
  MAX_PAGE_SIZE,
  DEFAULT_PAGE_SIZE,
} from "./api.ts";
import { z } from "zod";

const REQUEST_ID = "223e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "323e4567-e89b-12d3-a456-426614174000";
const LOG_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("API_VERSION", () => {
  test("is the fixed v1 constant", () => {
    assert.equal(API_VERSION, "v1");
  });
});

describe("buildApiError", () => {
  test("builds a well-formed ApiError with defaults", () => {
    const error = buildApiError({ code: "insufficient_authority", message: "denied", requestId: REQUEST_ID, now: new Date("2026-07-19T00:00:00.000Z") });
    assert.equal(error.code, "insufficient_authority");
    assert.deepEqual(error.details, []);
    assert.equal(error.requestId, REQUEST_ID);
    assert.equal(error.timestamp, "2026-07-19T00:00:00.000Z");
  });

  test("carries structured details when supplied", () => {
    const error = buildApiError({ code: "validation_failed", message: "invalid input", details: [{ field: "name", message: "required" }], requestId: REQUEST_ID });
    assert.equal(error.details.length, 1);
    assert.equal(error.details[0]?.field, "name");
  });
});

describe("CursorPaginationParamsSchema", () => {
  test("defaults limit to DEFAULT_PAGE_SIZE and cursor to null", () => {
    const parsed = CursorPaginationParamsSchema.parse({});
    assert.equal(parsed.limit, DEFAULT_PAGE_SIZE);
    assert.equal(parsed.cursor, null);
  });

  test("rejects a limit above MAX_PAGE_SIZE (unbounded-payload guard)", () => {
    assert.throws(() => CursorPaginationParamsSchema.parse({ limit: MAX_PAGE_SIZE + 1 }));
  });

  test("rejects a non-positive limit", () => {
    assert.throws(() => CursorPaginationParamsSchema.parse({ limit: 0 }));
  });
});

describe("OffsetPaginationParamsSchema", () => {
  test("defaults offset to 0 and limit to DEFAULT_PAGE_SIZE", () => {
    const parsed = OffsetPaginationParamsSchema.parse({});
    assert.equal(parsed.offset, 0);
    assert.equal(parsed.limit, DEFAULT_PAGE_SIZE);
  });

  test("rejects a negative offset", () => {
    assert.throws(() => OffsetPaginationParamsSchema.parse({ offset: -1 }));
  });
});

describe("paginatedResultSchema", () => {
  test("wraps items and pageInfo for an arbitrary item schema", () => {
    const schema = paginatedResultSchema(z.object({ id: z.string() }));
    const parsed = schema.parse({
      items: [{ id: "a" }, { id: "b" }],
      pageInfo: { hasNextPage: true, hasPreviousPage: false, nextCursor: "cursor-2", previousCursor: null },
    });
    assert.equal(parsed.items.length, 2);
    assert.equal(parsed.pageInfo.hasNextPage, true);
  });
});

describe("IdempotencyKeySchema / CorrelationIdSchema", () => {
  test("IdempotencyKeySchema rejects an empty string", () => {
    assert.throws(() => IdempotencyKeySchema.parse(""));
  });

  test("CorrelationIdSchema requires a real uuid", () => {
    assert.throws(() => CorrelationIdSchema.parse("not-a-uuid"));
    assert.equal(CorrelationIdSchema.parse(REQUEST_ID), REQUEST_ID);
  });
});

describe("parseApiLog", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const log = parseApiLog({
      id: LOG_ID,
      correlation_id: REQUEST_ID,
      tenant_id: TENANT_ID,
      actor_auth_user_id: null,
      actor_type: "api_key",
      api_key_id: "523e4567-e89b-12d3-a456-426614174000",
      interface: "rest",
      operation: "GET /v1/tenants",
      http_method: "GET",
      path: "/v1/tenants",
      graphql_operation_name: null,
      status_code: 200,
      result: "success",
      error_code: null,
      idempotency_key: null,
      duration_ms: 42,
      created_at: "2026-07-19T00:00:00.000Z",
    });
    assert.equal(log.actorType, "api_key");
    assert.equal(log.durationMs, 42);
  });
});
