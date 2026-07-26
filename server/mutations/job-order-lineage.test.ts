import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { prepareJobOrderHandoff, JobOrderLineageMutationError, type JobOrderLineageMutationRpcClient } from "./job-order-lineage.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "323e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: JobOrderLineageMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as JobOrderLineageMutationRpcClient;
  return { client, calls };
}

const VALID_PAYLOAD = {
  schemaVersion: 1,
  source: {
    quotationId: QUOTATION_ID,
    quoteNumber: "QTN-2026-000001",
    versionNumber: 1,
    opportunityId: "723e4567-e89b-12d3-a456-426614174000",
    prospectId: "823e4567-e89b-12d3-a456-426614174000",
    accountConversionId: "923e4567-e89b-12d3-a456-426614174000",
  },
  customer: {
    accountId: ACCOUNT_ID,
    customerSnapshot: { legal_name: "Lineage Co" },
    contactId: null,
    contactName: null,
    contactEmail: null,
    contactPhone: null,
  },
  cargoService: { service_type: "ocean_freight" },
  pricing: { currency: "IDR", subtotalAmount: 15000000, discountAmount: 0, taxAmount: 0, totalAmount: 15000000, lines: [] },
  contract: null,
  credit: null,
  acceptance: { decidedByName: "Lineage Contact", decidedAt: "2026-07-26T00:00:00.000Z", decision: "accepted" },
};

const UNMASKED_ROW = {
  id: HANDOFF_ID,
  tenant_id: TENANT_ID,
  quotation_id: QUOTATION_ID,
  account_id: ACCOUNT_ID,
  purpose: "job_order_draft",
  schema_version: 1,
  status: "prepared",
  payload: VALID_PAYLOAD,
  payload_hash: "abc123",
  downstream_reference: null,
  delivered_at: null,
  prepared_by_auth_user_id: ACTOR_ID,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  created_by: "tester",
  created_at: "2026-07-26T00:00:00.000Z",
};

describe("prepareJobOrderHandoff", () => {
  test("calls prepare_job_order_handoff with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: UNMASKED_ROW, error: null });
    const handoff = await prepareJobOrderHandoff(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "prepare_job_order_handoff");
    assert.deepEqual(calls[0]?.args, { p_quotation_id: QUOTATION_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "tester" });
    assert.equal(handoff.status, "prepared");
    assert.equal(handoff.payloadMasked, false);
  });

  test("synthesizes payloadMasked=true when the RPC's own row already carries a null payload", async () => {
    const { client } = fakeRpcClient({ data: { ...UNMASKED_ROW, payload: null, payload_hash: null }, error: null });
    const handoff = await prepareJobOrderHandoff(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(handoff.payloadMasked, true);
    assert.equal(handoff.payload, null);
  });

  test("classifies quote_not_accepted", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "quote_not_accepted: quotation has not been accepted by the customer" } });
    await assert.rejects(
      () => prepareJobOrderHandoff(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof JobOrderLineageMutationError);
        assert.equal(err.code, "quote_not_accepted");
        return true;
      },
    );
  });

  test("classifies account_not_converted", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "account_not_converted: quotation has not been converted to an account" } });
    await assert.rejects(
      () => prepareJobOrderHandoff(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof JobOrderLineageMutationError);
        assert.equal(err.code, "account_not_converted");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () => prepareJobOrderHandoff(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof JobOrderLineageMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
