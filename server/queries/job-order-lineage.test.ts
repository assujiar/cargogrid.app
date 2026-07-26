import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getJobOrderHandoffForQuotation, listJobOrderHandoffs, JobOrderLineageQueryError, type JobOrderLineageQueryTableClient } from "./job-order-lineage.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "323e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const MASKED_ROW = {
  id: HANDOFF_ID,
  tenant_id: TENANT_ID,
  quotation_id: QUOTATION_ID,
  account_id: ACCOUNT_ID,
  purpose: "job_order_draft",
  schema_version: 1,
  status: "prepared",
  payload: null,
  payload_hash: null,
  payload_masked: true,
  downstream_reference: null,
  delivered_at: null,
  prepared_by_auth_user_id: ACTOR_ID,
  owner_user_id: null,
  org_unit_id: null,
  created_by: "tester",
  created_at: "2026-07-26T00:00:00.000Z",
};

function fakeTableClient(response: { data: unknown; error: { message: string } | null }): JobOrderLineageQueryTableClient {
  function chainNode(): unknown {
    return {
      select: () => chainNode(),
      eq: () => chainNode(),
      order: () => chainNode(),
      limit: () => Promise.resolve(response),
      maybeSingle: () => {
        const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
        return Promise.resolve({ data: row, error: response.error });
      },
      then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) => Promise.resolve(response).then(resolve, reject),
    };
  }
  return { from: () => chainNode() } as unknown as JobOrderLineageQueryTableClient;
}

describe("getJobOrderHandoffForQuotation", () => {
  test("returns null (never an error) when no handoff has been prepared yet", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const handoff = await getJobOrderHandoffForQuotation(client, QUOTATION_ID);
    assert.equal(handoff, null);
  });

  test("maps a masked row", async () => {
    const client = fakeTableClient({ data: MASKED_ROW, error: null });
    const handoff = await getJobOrderHandoffForQuotation(client, QUOTATION_ID);
    assert.equal(handoff?.payloadMasked, true);
    assert.equal(handoff?.payload, null);
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getJobOrderHandoffForQuotation(client, QUOTATION_ID),
      (err: unknown) => err instanceof JobOrderLineageQueryError,
    );
  });
});

describe("listJobOrderHandoffs", () => {
  test("maps rows", async () => {
    const client = fakeTableClient({ data: [MASKED_ROW], error: null });
    const handoffs = await listJobOrderHandoffs(client, TENANT_ID);
    assert.equal(handoffs.length, 1);
    assert.equal(handoffs[0]?.status, "prepared");
  });
});
