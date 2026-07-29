import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { setFinanceAgingBucketConfig, AgingMutationError, type AgingMutationRpcClient } from "./aging.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONFIG_ID = "323e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const CONFIG_ROW = {
  id: CONFIG_ID, tenant_id: TENANT_ID, entity_type: "ar", version: 1,
  buckets: [
    { label: "Current", minDays: -999999, maxDays: 0 },
    { label: "1-45", minDays: 1, maxDays: 45 },
    { label: "46+", minDays: 46, maxDays: null },
  ],
  is_active: true, created_by: "fm", created_at: "2026-07-01T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): AgingMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AgingMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("setFinanceAgingBucketConfig", () => {
  test("calls set_finance_aging_bucket_config with exact snake_case params", async () => {
    const client = fakeClient({ data: CONFIG_ROW, error: null });
    const config = await setFinanceAgingBucketConfig(client, {
      tenantId: TENANT_ID, entityType: "ar",
      buckets: [
        { label: "Current", minDays: -999999, maxDays: 0 },
        { label: "1-45", minDays: 1, maxDays: 45 },
        { label: "46+", minDays: 46, maxDays: null },
      ],
      actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "set_finance_aging_bucket_config");
    assert.equal(config.version, 1);
  });

  test("wraps a finance_aging_bucket_gap_or_overlap error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_aging_bucket_gap_or_overlap: bucket 2 starts at 50 but the previous bucket ended at 45" } });
    await assert.rejects(
      () => setFinanceAgingBucketConfig(client, {
        tenantId: TENANT_ID, entityType: "ar",
        buckets: [
          { label: "Current", minDays: -999999, maxDays: 0 },
          { label: "1-45", minDays: 1, maxDays: 45 },
          { label: "50+", minDays: 50, maxDays: null },
        ],
        actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
      (error: unknown) => error instanceof AgingMutationError && error.code === "finance_aging_bucket_gap_or_overlap",
    );
  });
});
