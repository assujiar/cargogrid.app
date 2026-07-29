import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getFinanceIdempotencyClaim, IdempotencyQueryError, type IdempotencyQueryRpcClient } from "./idempotency.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CLAIM_ID = "323e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): IdempotencyQueryRpcClient {
  return { async rpc() { return response; } } as unknown as IdempotencyQueryRpcClient;
}

describe("getFinanceIdempotencyClaim", () => {
  test("maps a claim row to camelCase", async () => {
    const client = fakeClient({
      data: {
        id: CLAIM_ID, tenant_id: TENANT_ID, scope: "journal", idempotency_key: "jrnl-1", request_fingerprint: "abc123",
        status: "completed", result_entity_type: "journal", result_entity_id: "323e4567-e89b-12d3-a456-426614174000", error_message: null,
        claimed_by: "fm", claimed_at: "2026-06-01T00:00:00.000Z", completed_at: "2026-06-01T00:00:01.000Z", created_at: "2026-06-01T00:00:00.000Z",
      },
      error: null,
    });
    const claim = await getFinanceIdempotencyClaim(client, { tenantId: TENANT_ID, scope: "journal", idempotencyKey: "jrnl-1", actorAuthUserId: ACTOR_ID });
    assert.equal(claim.status, "completed");
  });

  test("throws on a finance_idempotency_claim_not_found rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_idempotency_claim_not_found: no claim for scope journal key jrnl-missing" } });
    await assert.rejects(
      () => getFinanceIdempotencyClaim(client, { tenantId: TENANT_ID, scope: "journal", idempotencyKey: "jrnl-missing", actorAuthUserId: ACTOR_ID }),
      IdempotencyQueryError,
    );
  });
});
