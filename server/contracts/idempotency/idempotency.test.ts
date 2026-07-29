import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { FinanceIdempotencyClaimStatusSchema, parseFinanceIdempotencyClaim } from "./idempotency.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CLAIM_ID = "323e4567-e89b-12d3-a456-426614174001";
const JOURNAL_ID = "323e4567-e89b-12d3-a456-426614174000";

describe("FinanceIdempotencyClaimStatusSchema", () => {
  test("accepts claimed/completed/failed", () => {
    for (const status of ["claimed", "completed", "failed"]) {
      assert.doesNotThrow(() => FinanceIdempotencyClaimStatusSchema.parse(status));
    }
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() => FinanceIdempotencyClaimStatusSchema.parse("pending"));
  });
});

describe("parseFinanceIdempotencyClaim", () => {
  test("maps a completed claim row to camelCase", () => {
    const parsed = parseFinanceIdempotencyClaim({
      id: CLAIM_ID, tenant_id: TENANT_ID, scope: "journal", idempotency_key: "jrnl-1", request_fingerprint: "abc123",
      status: "completed", result_entity_type: "journal", result_entity_id: JOURNAL_ID, error_message: null,
      claimed_by: "fm", claimed_at: "2026-06-01T00:00:00.000Z", completed_at: "2026-06-01T00:00:01.000Z", created_at: "2026-06-01T00:00:00.000Z",
    });
    assert.equal(parsed.status, "completed");
    assert.equal(parsed.resultEntityId, JOURNAL_ID);
  });

  test("maps a claimed (not yet completed) row with null result fields", () => {
    const parsed = parseFinanceIdempotencyClaim({
      id: CLAIM_ID, tenant_id: TENANT_ID, scope: "journal", idempotency_key: "jrnl-2", request_fingerprint: "def456",
      status: "claimed", result_entity_type: null, result_entity_id: null, error_message: null,
      claimed_by: "fm", claimed_at: "2026-06-01T00:00:00.000Z", completed_at: null, created_at: "2026-06-01T00:00:00.000Z",
    });
    assert.equal(parsed.status, "claimed");
    assert.equal(parsed.resultEntityId, null);
  });
});
