import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  sendQuotationForAcceptance,
  revokeQuotationAcceptanceToken,
  recordQuotationCustomerDecision,
  QuotationAcceptanceMutationError,
  type QuotationAcceptanceMutationRpcClient,
} from "./quotation-acceptance.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "323e4567-e89b-12d3-a456-426614174000";
const TOKEN_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "623e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_QUOTATION_ROW = {
  id: QUOTATION_ID,
  tenant_id: TENANT_ID,
  quote_number: "QTN-2026-000001",
  opportunity_id: OPPORTUNITY_ID,
  source_opportunity_version: 1,
  prospect_id: PROSPECT_ID,
  contact_id: null,
  customer_snapshot: {},
  currency: "IDR",
  validity_from: "2026-07-24T00:00:00.000Z",
  validity_to: "2026-08-24T00:00:00.000Z",
  terms: {},
  subtotal_amount: 15000000,
  discount_amount: 0,
  tax_amount: 0,
  total_amount: 15000000,
  sell_masked: false,
  status: "submitted",
  cancel_reason: null,
  cloned_from_id: null,
  document_ref: null,
  submitted_at: "2026-07-24T00:00:00.000Z",
  submitted_by: "tester",
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 2,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
  root_quotation_id: QUOTATION_ID,
  version_number: 1,
  is_current: true,
  superseded_by_id: null,
  revision_reason: null,
  approval_status: "not_required",
  approval_request_id: null,
  approval_rule_version_id: null,
  approval_required_reasons: [],
  customer_decision: "accepted",
  customer_decision_at: "2026-07-24T01:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): QuotationAcceptanceMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as QuotationAcceptanceMutationRpcClient;
}

describe("sendQuotationForAcceptance", () => {
  test("calls send_quotation_for_acceptance with the exact snake_case params and parses a single-row array response", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [{ token_id: TOKEN_ID, raw_token: "deadbeef", expires_at: "2026-08-24T00:00:00.000Z", quotation_id: QUOTATION_ID }], error: null }, calls);
    const result = await sendQuotationForAcceptance(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "send_quotation_for_acceptance");
    assert.equal(calls[0]?.args.p_channel, "email");
    assert.equal(result.rawToken, "deadbeef");
  });

  test("classifies quotation_not_acceptance_eligible", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "quotation_not_acceptance_eligible: quotation x is draft (must be submitted)" } }, []);
    await assert.rejects(
      () => sendQuotationForAcceptance(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationAcceptanceMutationError);
        assert.equal(err.code, "quotation_not_acceptance_eligible");
        return true;
      },
    );
  });
});

describe("revokeQuotationAcceptanceToken", () => {
  test("calls revoke_quotation_acceptance_token with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient(
      { data: { id: TOKEN_ID, tenant_id: TENANT_ID, quotation_id: QUOTATION_ID, status: "revoked", channel: "email", recipient_contact_id: null, recipient_email: null, expires_at: "2026-08-24T00:00:00.000Z", sent_at: "2026-07-24T00:00:00.000Z", sent_by: "tester", revoked_at: "2026-07-24T02:00:00.000Z", revoked_reason: "customer requested resend", consumed_at: null, created_by: "tester", created_at: "2026-07-24T00:00:00.000Z" }, error: null },
      calls,
    );
    const token = await revokeQuotationAcceptanceToken(client, { tokenId: TOKEN_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", reason: "customer requested resend" });
    assert.equal(calls[0]?.fn, "revoke_quotation_acceptance_token");
    assert.equal(calls[0]?.args.p_reason, "customer requested resend");
    assert.equal(token.status, "revoked");
  });

  test("classifies token_not_active", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "token_not_active: token x is revoked, only an active token can be revoked" } }, []);
    await assert.rejects(
      () => revokeQuotationAcceptanceToken(client, { tokenId: TOKEN_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", reason: "second attempt" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationAcceptanceMutationError);
        assert.equal(err.code, "token_not_active");
        return true;
      },
    );
  });
});

describe("recordQuotationCustomerDecision", () => {
  test("calls record_quotation_customer_decision with the exact snake_case params and parses the returned quotation", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_QUOTATION_ROW, error: null }, calls);
    const quotation = await recordQuotationCustomerDecision(client, { rawToken: "deadbeef", decision: "accepted", decidedByName: "Jane Doe" });
    assert.equal(calls[0]?.fn, "record_quotation_customer_decision");
    assert.equal(calls[0]?.args.p_decision, "accepted");
    assert.equal(calls[0]?.args.p_reason, null);
    assert.equal(quotation.customerDecision, "accepted");
  });

  test("classifies token_already_consumed", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "token_already_consumed: token x has already recorded a decision" } }, []);
    await assert.rejects(
      () => recordQuotationCustomerDecision(client, { rawToken: "deadbeef", decision: "accepted", decidedByName: "Jane Doe" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationAcceptanceMutationError);
        assert.equal(err.code, "token_already_consumed");
        return true;
      },
    );
  });

  test("classifies reason_required for a reject without a reason", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "reason_required: a reason is required to reject" } }, []);
    await assert.rejects(
      () => recordQuotationCustomerDecision(client, { rawToken: "deadbeef", decision: "rejected", decidedByName: "Jane Doe" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationAcceptanceMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });
});
