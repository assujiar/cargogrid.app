import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getFinanceAgingReport, getFinanceAgingSummary, listFinanceAgingBucketConfigs, AgingQueryError, type AgingQueryRpcClient } from "./aging.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "323e4567-e89b-12d3-a456-426614174000";
const PARTY_ID = "423e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "523e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): AgingQueryRpcClient {
  return { async rpc() { return response; } } as unknown as AgingQueryRpcClient;
}

describe("getFinanceAgingReport", () => {
  test("maps rows to camelCase", async () => {
    const client = fakeClient({
      data: [{
        open_item_id: ITEM_ID, party_id: PARTY_ID, currency: "USD", original_amount: "1000.00", open_amount: "400.00",
        document_date: "2026-05-01", due_date: "2026-05-31", days_overdue: 45, bucket_label: "31-60", is_held: false,
        source_document_type: "invoice", source_document_id: SOURCE_ID,
      }],
      error: null,
    });
    const rows = await getFinanceAgingReport(client, { tenantId: TENANT_ID, companyId: null, entityType: "ar", asOfDate: "2026-07-15", includeHeld: true, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.bucketLabel, "31-60");
  });

  test("throws on rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: lacks FIN:View" } });
    await assert.rejects(() => getFinanceAgingReport(client, { tenantId: TENANT_ID, companyId: null, entityType: "ar", asOfDate: "2026-07-15", includeHeld: true, actorAuthUserId: ACTOR_ID }), AgingQueryError);
  });
});

describe("getFinanceAgingSummary", () => {
  test("maps summary rows to camelCase", async () => {
    const client = fakeClient({ data: [{ bucket_label: "31-60", currency: "USD", open_amount: "400.00", item_count: "1" }], error: null });
    const rows = await getFinanceAgingSummary(client, { tenantId: TENANT_ID, companyId: null, entityType: "ar", asOfDate: "2026-07-15", includeHeld: true, actorAuthUserId: ACTOR_ID });
    assert.equal(rows[0]?.itemCount, 1);
  });
});

describe("listFinanceAgingBucketConfigs", () => {
  test("maps config rows to camelCase", async () => {
    const client = fakeClient({
      data: [{
        id: "623e4567-e89b-12d3-a456-426614174002", tenant_id: TENANT_ID, entity_type: "ar", version: 1,
        buckets: [{ label: "Current", minDays: -999999, maxDays: 0 }], is_active: true, created_by: "fm", created_at: "2026-07-01T00:00:00.000Z",
      }],
      error: null,
    });
    const rows = await listFinanceAgingBucketConfigs(client, { tenantId: TENANT_ID, entityType: "ar", actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.version, 1);
  });
});
