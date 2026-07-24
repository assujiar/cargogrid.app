import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getQuotationById,
  listQuotationsForOpportunity,
  listQuotationsForTenant,
  listQuotationLines,
  getQuotationSubmissionReadiness,
  QuotationQueryError,
  type QuotationQueryTableClient,
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
};

function fakeTableClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): QuotationQueryTableClient {
  function chain(): Record<string, unknown> {
    return {
      eq(column: string, value: unknown) {
        const eqCalls = (capture.calls.eqCalls ?? []) as { column: string; value: unknown }[];
        eqCalls.push({ column, value });
        capture.calls.eqCalls = eqCalls;
        return chain();
      },
      order(column: string, opts: { ascending: boolean }) {
        capture.calls.orderColumn = column;
        capture.calls.ascending = opts.ascending;
        return response;
      },
      async maybeSingle() {
        const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
        return { data: row, error: response.error };
      },
    };
  }

  const fake = {
    from(table: string) {
      capture.calls.table = table;
      return { select: () => chain() };
    },
  };
  return fake as unknown as QuotationQueryTableClient;
}

describe("getQuotationById", () => {
  test("reads from quotations_directory and returns null when not found", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    const quotation = await getQuotationById(client, QUOTATION_ID);
    assert.equal(capture.calls.table, "quotations_directory");
    assert.equal(quotation, null);
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } }, { calls: {} });
    await assert.rejects(
      () => getQuotationById(client, QUOTATION_ID),
      (err: unknown) => {
        assert.ok(err instanceof QuotationQueryError);
        return true;
      },
    );
  });
});

describe("listQuotationsForOpportunity", () => {
  test("filters by opportunity_id, newest first", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_QUOTATION_ROW], error: null }, capture);
    const quotations = await listQuotationsForOpportunity(client, OPPORTUNITY_ID);
    const eqCalls = capture.calls.eqCalls as { column: string; value: unknown }[];
    assert.deepEqual(eqCalls, [{ column: "opportunity_id", value: OPPORTUNITY_ID }]);
    assert.equal(capture.calls.ascending, false);
    assert.equal(quotations[0]?.quoteNumber, "QTN-2026-000001");
  });
});

describe("listQuotationsForTenant", () => {
  test("filters by tenant_id", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_QUOTATION_ROW], error: null }, capture);
    await listQuotationsForTenant(client, TENANT_ID);
    const eqCalls = capture.calls.eqCalls as { column: string; value: unknown }[];
    assert.deepEqual(eqCalls, [{ column: "tenant_id", value: TENANT_ID }]);
  });
});

describe("listQuotationLines", () => {
  test("queries the field-masked quotation_lines_directory view, ordered by line_no ascending", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    await listQuotationLines(client, QUOTATION_ID);
    assert.equal(capture.calls.table, "quotation_lines_directory");
    assert.equal(capture.calls.orderColumn, "line_no");
    assert.equal(capture.calls.ascending, true);
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
