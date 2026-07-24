import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { convertQuotationToAccount, AccountMutationError, type AccountMutationRpcClient } from "./account.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "623e4567-e89b-12d3-a456-426614174000";

const ACCOUNT_ROW = {
  id: ACCOUNT_ID,
  tenant_id: TENANT_ID,
  legal_name: "Contoso Ltd",
  trade_name: null,
  tax_id: null,
  billing_address: {},
  customer_status: "active",
  parent_account_id: null,
  source_prospect_id: null,
  status: "active",
  merged_into_id: null,
  merged_at: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): AccountMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AccountMutationRpcClient;
}

describe("convertQuotationToAccount", () => {
  test("calls convert_quotation_to_account with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: ACCOUNT_ROW, error: null }, calls);
    const account = await convertQuotationToAccount(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "convert_quotation_to_account");
    assert.equal(calls[0]?.args.p_target_account_id, null);
    assert.equal(calls[0]?.args.p_parent_account_id, null);
    assert.equal(account.legalName, "Contoso Ltd");
  });

  test("passes targetAccountId for the link-to-existing flow", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: ACCOUNT_ROW, error: null }, calls);
    await convertQuotationToAccount(client, { quotationId: QUOTATION_ID, targetAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.args.p_target_account_id, ACCOUNT_ID);
  });

  test("classifies quotation_not_accepted", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "quotation_not_accepted: quotation x has no accepted customer decision" } }, []);
    await assert.rejects(
      () => convertQuotationToAccount(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof AccountMutationError);
        assert.equal(err.code, "quotation_not_accepted");
        return true;
      },
    );
  });

  test("classifies insufficient_authority", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks COM:Approve (missing) for tenant y" } }, []);
    await assert.rejects(
      () => convertQuotationToAccount(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof AccountMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});
