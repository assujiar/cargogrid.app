import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getNumberingAllocationStatus, formatNumberingPreview, NumberingQueryError, type NumberingQueryRpcClient } from "./numbering.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ALLOCATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): NumberingQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("getNumberingAllocationStatus", () => {
  test("calls get_numbering_allocation_status with the exact snake_case params and maps the row", async () => {
    const client = fakeClient({
      data: {
        id: ALLOCATION_ID,
        tenant_id: TENANT_ID,
        config_version_id: VERSION_ID,
        scope_key: "default",
        period_key: "2026",
        seq: 1,
        formatted_number: "INV-2026-000001",
        entity_type: "generic",
        entity_id: null,
        status: "allocated",
        idempotency_key: "num-9001",
        allocated_by: "tenant user",
        allocated_at: "2026-07-19T00:00:00.000Z",
        voided_at: null,
        voided_reason: null,
        record_version: 1,
        created_at: "2026-07-19T00:00:00.000Z",
        updated_at: "2026-07-19T00:00:00.000Z",
      },
      error: null,
    });

    const allocation = await getNumberingAllocationStatus(client, { allocationId: ALLOCATION_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(client.calls[0]?.args, { p_allocation_id: ALLOCATION_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(allocation.formattedNumber, "INV-2026-000001");
  });

  test("throws NumberingQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x is not an active member of tenant y" } });
    await assert.rejects(() => getNumberingAllocationStatus(client, { allocationId: ALLOCATION_ID, actorAuthUserId: ACTOR_ID }));
  });
});

describe("formatNumberingPreview", () => {
  test("calls format_numbering_value and omits p_as_of when asOf is null", async () => {
    const client = fakeClient({ data: "INV-2026-000042", error: null });
    const formatted = await formatNumberingPreview(client, { format: "INV-{YYYY}-{SEQ}", seq: 42, padding: 6 });

    assert.deepEqual(client.calls[0]?.args, {
      p_format: "INV-{YYYY}-{SEQ}",
      p_seq: 42,
      p_padding: 6,
      p_scope_code: null,
    });
    assert.equal(formatted, "INV-2026-000042");
  });

  test("includes p_as_of when explicitly provided", async () => {
    const client = fakeClient({ data: "INV-2026-000042", error: null });
    await formatNumberingPreview(client, { format: "INV-{YYYY}-{SEQ}", seq: 42, padding: 6, asOf: "2026-07-19T00:00:00.000Z" });

    assert.equal(client.calls[0]?.args["p_as_of"], "2026-07-19T00:00:00.000Z");
  });

  test("throws NumberingQueryError if data is not a string", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(() => formatNumberingPreview(client, { format: "INV-{SEQ}", seq: 1, padding: 3 }));
  });
});
