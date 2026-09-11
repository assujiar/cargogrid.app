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

function fakeRpcClient(
  responses: Record<string, { data: unknown; error: { message: string } | null }>,
  capture?: { calls: { fn: string; args: Record<string, unknown> }[] },
): JobOrderLineageQueryTableClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture?.calls.push({ fn, args });
      return responses[fn] ?? { data: null, error: { message: `no mock response for ${fn}` } };
    },
  } as unknown as JobOrderLineageQueryTableClient;
}

describe("getJobOrderHandoffForQuotation", () => {
  test("returns null (never an error) when no handoff has been prepared yet", async () => {
    const client = fakeRpcClient({ get_job_order_handoff_for_quotation: { data: [], error: null } });
    const handoff = await getJobOrderHandoffForQuotation(client, QUOTATION_ID, ACTOR_ID);
    assert.equal(handoff, null);
  });

  test("maps a masked row", async () => {
    const client = fakeRpcClient({ get_job_order_handoff_for_quotation: { data: [MASKED_ROW], error: null } });
    const handoff = await getJobOrderHandoffForQuotation(client, QUOTATION_ID, ACTOR_ID);
    assert.equal(handoff?.payloadMasked, true);
    assert.equal(handoff?.payload, null);
  });

  test("calls get_job_order_handoff_for_quotation with the quotation id and actor id", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ get_job_order_handoff_for_quotation: { data: [MASKED_ROW], error: null } }, capture);
    await getJobOrderHandoffForQuotation(client, QUOTATION_ID, ACTOR_ID);
    assert.deepEqual(capture.calls[0], {
      fn: "get_job_order_handoff_for_quotation",
      args: { p_quotation_id: QUOTATION_ID, p_actor_auth_user_id: ACTOR_ID },
    });
  });

  test("wraps a query error, including an ambiguous_context conflict", async () => {
    const client = fakeRpcClient({ get_job_order_handoff_for_quotation: { data: null, error: { message: "boom" } } });
    await assert.rejects(
      () => getJobOrderHandoffForQuotation(client, QUOTATION_ID, ACTOR_ID),
      (err: unknown) => err instanceof JobOrderLineageQueryError,
    );
  });
});

describe("listJobOrderHandoffs", () => {
  test("maps rows and passes tenant id, actor id, and the default limit", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ list_job_order_handoffs: { data: [MASKED_ROW], error: null } }, capture);
    const handoffs = await listJobOrderHandoffs(client, TENANT_ID, ACTOR_ID);
    assert.equal(handoffs.length, 1);
    assert.equal(handoffs[0]?.status, "prepared");
    assert.deepEqual(capture.calls[0], {
      fn: "list_job_order_handoffs",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_limit: 50 },
    });
  });

  test("passes a caller-supplied limit through", async () => {
    const capture = { calls: [] as { fn: string; args: Record<string, unknown> }[] };
    const client = fakeRpcClient({ list_job_order_handoffs: { data: [], error: null } }, capture);
    await listJobOrderHandoffs(client, TENANT_ID, ACTOR_ID, 10);
    assert.equal(capture.calls[0]?.args.p_limit, 10);
  });

  test("returns an empty array, not an error, for a tenant with zero visible handoffs", async () => {
    const client = fakeRpcClient({ list_job_order_handoffs: { data: [], error: null } });
    assert.deepEqual(await listJobOrderHandoffs(client, TENANT_ID, ACTOR_ID), []);
  });
});
