import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceAccounts, getFinanceAccountDependencyImpact, ChartOfAccountsQueryError, type ChartOfAccountsQueryRpcClient } from "./chart-of-accounts.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const ACCOUNT_ROW = {
  id: ACCOUNT_ID,
  tenant_id: TENANT_ID,
  company_id: null,
  code: "1200-AR",
  name: "Accounts Receivable",
  account_type: "asset",
  normal_balance: "debit",
  parent_account_id: null,
  is_control_account: false,
  is_postable: true,
  currency_restriction: null,
  status: "active",
  record_version: 1,
  created_by: "finance-admin",
  created_at: "2026-07-28T00:00:00.000Z",
  updated_at: "2026-07-28T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): ChartOfAccountsQueryRpcClient & { calls: number } {
  let calls = 0;
  return {
    get calls() {
      return calls;
    },
    async rpc(_fn: string, _args: Record<string, unknown>) {
      calls += 1;
      return response;
    },
  } as unknown as ChartOfAccountsQueryRpcClient & { calls: number };
}

describe("listFinanceAccounts", () => {
  test("maps every returned row to the FinanceAccount contract shape", async () => {
    const client = fakeClient({ data: [ACCOUNT_ROW], error: null });
    const accounts = await listFinanceAccounts(client, { tenantId: TENANT_ID, companyId: null, status: "active", actorAuthUserId: ACTOR_ID });
    assert.equal(accounts.length, 1);
    assert.equal(accounts[0]?.code, "1200-AR");
  });

  test("wraps a database error into a typed ChartOfAccountsQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(() => listFinanceAccounts(client, { tenantId: TENANT_ID, companyId: null, status: null, actorAuthUserId: ACTOR_ID }), ChartOfAccountsQueryError);
  });
});

describe("getFinanceAccountDependencyImpact", () => {
  test("parses a structural dependency-impact result", async () => {
    const client = fakeClient({ data: { accountId: ACCOUNT_ID, code: "1200-AR", activeChildAccountCount: 1, referencedByPublishedPostingMap: false }, error: null });
    const impact = await getFinanceAccountDependencyImpact(client, ACCOUNT_ID, ACTOR_ID);
    assert.equal(impact.activeChildAccountCount, 1);
    assert.equal(impact.referencedByPublishedPostingMap, false);
  });

  test("throws ChartOfAccountsQueryError when the RPC returns no result", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(() => getFinanceAccountDependencyImpact(client, ACCOUNT_ID, ACTOR_ID), ChartOfAccountsQueryError);
  });
});
