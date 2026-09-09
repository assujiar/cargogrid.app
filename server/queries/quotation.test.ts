import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getQuotationById,
  listQuotationVersions,
  listQuotationsForOpportunity,
  listQuotationsForTenant,
  listQuotationLines,
  getQuotationSubmissionReadiness,
  QuotationQueryError,
  type QuotationQueryRpcClient,
  type QuotationReadinessRpcClient,
} from "./quotation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "323e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_QUOTATION_ROW = {
  id: QUOTATION_ID,
  tenant_id: TENANT_ID,
  quote_number: "QTN-2026-000001",
  opportunity_id: OPPORTUNITY_ID,
  source_opportunity_version: 1,
  prospect_id: "623e4567-e89b-12d3-a456-426614174000",
  contact_id: null,
  customer_snapshot: { legal_name: "Contoso Ltd" },
  currency: "IDR",
  validity_from: "2026-07-24T00:00:00.000Z",
  validity_to: "2026-08-24T00:00:00.000Z",
  terms: {},
  subtotal_amount: 15000000,
  discount_amount: 0,
  tax_amount: 0,
  total_amount: 15000000,
  sell_masked: false,
  status: "draft",
  cancel_reason: null,
  cloned_from_id: null,
  document_ref: null,
  submitted_at: null,
  submitted_by: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
  root_quotation_id: QUOTATION_ID,
  version_number: 1,
  is_current: true,
  superseded_by_id: null,
  revision_reason: null,
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): QuotationQueryRpcClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.fn = fn;
      capture.calls.args = args;
      return response;
    },
  };
  return fake as unknown as QuotationQueryRpcClient;
}

describe("getQuotationById", () => {
  test("calls get_quotation_by_id and returns null when not found", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [], error: null }, capture);
    const quotation = await getQuotationById(client, QUOTATION_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "get_quotation_by_id");
    assert.deepEqual(capture.calls.args, { p_quotation_id: QUOTATION_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(quotation, null);
  });

  test("wraps a query error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } }, { calls: {} });
    await assert.rejects(
      () => getQuotationById(client, QUOTATION_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof QuotationQueryError);
        return true;
      },
    );
  });
});

describe("listQuotationVersions", () => {
  test("calls list_quotation_versions with root_quotation_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [VALID_QUOTATION_ROW], error: null }, capture);
    const versions = await listQuotationVersions(client, QUOTATION_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_quotation_versions");
    assert.deepEqual(capture.calls.args, { p_root_quotation_id: QUOTATION_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(versions[0]?.versionNumber, 1);
  });
});

describe("listQuotationsForOpportunity", () => {
  test("calls list_quotations_for_opportunity with opportunity_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [VALID_QUOTATION_ROW], error: null }, capture);
    const quotations = await listQuotationsForOpportunity(client, OPPORTUNITY_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_quotations_for_opportunity");
    assert.deepEqual(capture.calls.args, { p_opportunity_id: OPPORTUNITY_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(quotations[0]?.quoteNumber, "QTN-2026-000001");
  });
});

describe("listQuotationsForTenant", () => {
  test("calls list_quotations_for_tenant with tenant/actor/limit", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [VALID_QUOTATION_ROW], error: null }, capture);
    const quotations = await listQuotationsForTenant(client, TENANT_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_quotations_for_tenant");
    assert.deepEqual(capture.calls.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_limit: 200 });
    assert.equal(quotations.truncated, false);
  });

  test("reports truncated when the row count reaches the cap", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const rows = Array.from({ length: 200 }, () => VALID_QUOTATION_ROW);
    const client = fakeRpcClient({ data: rows, error: null }, capture);
    const quotations = await listQuotationsForTenant(client, TENANT_ID, ACTOR_ID);
    // ISS-2026-238: the cap is asserted, not assumed -- this read used to fetch every quotation
    // for the tenant on every page load, and nothing in the suite would have noticed.
    assert.equal(quotations.truncated, true);
  });
});

describe("listQuotationLines", () => {
  test("calls list_quotation_lines with quotation_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [], error: null }, capture);
    await listQuotationLines(client, QUOTATION_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_quotation_lines");
    assert.deepEqual(capture.calls.args, { p_quotation_id: QUOTATION_ID, p_actor_auth_user_id: ACTOR_ID });
  });
});

describe("getQuotationSubmissionReadiness", () => {
  test("parses a single-row RPC response", async () => {
    const client: QuotationReadinessRpcClient = {
      async rpc() {
        return { data: [{ ready: false, blocking_reasons: ["no_lines"] }], error: null };
      },
    } as unknown as QuotationReadinessRpcClient;
    const readiness = await getQuotationSubmissionReadiness(client, QUOTATION_ID, ACTOR_ID);
    assert.equal(readiness.ready, false);
    assert.deepEqual(readiness.blockingReasons, ["no_lines"]);
  });

  test("wraps an RPC error", async () => {
    const client: QuotationReadinessRpcClient = {
      async rpc() {
        return { data: null, error: { message: "insufficient_privilege: identity x cannot access quotation y" } };
      },
    } as unknown as QuotationReadinessRpcClient;
    await assert.rejects(
      () => getQuotationSubmissionReadiness(client, QUOTATION_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof QuotationQueryError);
        return true;
      },
    );
  });
});
