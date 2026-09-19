import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listQuotationAcceptanceTokens, getQuotationForCustomerDecision, QuotationAcceptanceQueryError, type QuotationAcceptanceQueryRpcClient } from "./quotation-acceptance.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "323e4567-e89b-12d3-a456-426614174000";
const TOKEN_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const TOKEN_ROW = {
  id: TOKEN_ID,
  tenant_id: TENANT_ID,
  quotation_id: QUOTATION_ID,
  status: "active",
  channel: "email",
  recipient_contact_id: null,
  recipient_email: "jane@contoso.test",
  expires_at: "2026-08-24T00:00:00.000Z",
  sent_at: "2026-07-24T00:00:00.000Z",
  sent_by: "tester",
  revoked_at: null,
  revoked_reason: null,
  consumed_at: null,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): QuotationAcceptanceQueryRpcClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.fn = fn;
      capture.calls.args = args;
      return response;
    },
  };
  return fake as unknown as QuotationAcceptanceQueryRpcClient;
}

describe("listQuotationAcceptanceTokens", () => {
  test("calls list_quotation_acceptance_tokens with quotation/actor, never selecting token_hash", () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [TOKEN_ROW], error: null }, capture);
    return listQuotationAcceptanceTokens(client, QUOTATION_ID, ACTOR_ID).then((tokens) => {
      assert.equal(capture.calls.fn, "list_quotation_acceptance_tokens");
      assert.deepEqual(capture.calls.args, { p_quotation_id: QUOTATION_ID, p_actor_auth_user_id: ACTOR_ID });
      assert.ok(!("token_hash" in TOKEN_ROW));
      assert.equal(tokens[0]?.status, "active");
    });
  });

  test("wraps a query error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } }, { calls: {} });
    await assert.rejects(
      () => listQuotationAcceptanceTokens(client, QUOTATION_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof QuotationAcceptanceQueryError);
        return true;
      },
    );
  });
});

describe("getQuotationForCustomerDecision", () => {
  test("calls get_quotation_for_customer_decision and parses a single-row array response", async () => {
    const client: QuotationAcceptanceQueryRpcClient = {
      async rpc() {
        return {
          data: [
            {
              token_status: "active",
              quotation_id: QUOTATION_ID,
              quote_number: "QTN-2026-000001",
              customer_snapshot: { legal_name: "Contoso Ltd" },
              currency: "IDR",
              validity_to: "2026-08-24T00:00:00.000Z",
              terms: {},
              subtotal_amount: 15000000,
              discount_amount: 0,
              tax_amount: 0,
              total_amount: 15000000,
              already_decided: false,
            },
          ],
          error: null,
        };
      },
    } as unknown as QuotationAcceptanceQueryRpcClient;

    const view = await getQuotationForCustomerDecision(client, { rawToken: "deadbeef" });
    assert.equal(view.quoteNumber, "QTN-2026-000001");
    assert.equal(view.tokenStatus, "active");
  });

  test("wraps an RPC error (e.g. token_not_found)", async () => {
    const client: QuotationAcceptanceQueryRpcClient = {
      async rpc() {
        return { data: null, error: { message: "token_not_found: presented token does not match any known token" } };
      },
    } as unknown as QuotationAcceptanceQueryRpcClient;
    await assert.rejects(() => getQuotationForCustomerDecision(client, { rawToken: "unknown" }));
  });
});
