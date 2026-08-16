import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomerPortalDashboardSummary, CustomerPortalDashboardQueryError, type CustomerPortalDashboardQueryClient } from "./customer-portal-dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const AUTH_USER_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalDashboardQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalDashboardQueryClient;
  return { client, calls };
}

const ACCOUNTS_ROW = {
  card_key: "accounts",
  available: true,
  source_updated_at: "2026-08-16T00:00:00.000Z",
  degraded: false,
  summary: { activeAccountCount: 1, primaryAccountName: "Dash Co" },
  detail_path: "customer-portal",
};

const STUB_ROW = {
  card_key: "loyalty",
  available: false,
  source_updated_at: null,
  degraded: false,
  summary: {},
  detail_path: null,
};

describe("getCustomerPortalDashboardSummary", () => {
  test("passes the exact param names and maps every returned card", async () => {
    const { client, calls } = fakeRpcClient({ data: [ACCOUNTS_ROW, STUB_ROW], error: null });
    const result = await getCustomerPortalDashboardSummary(client, AUTH_USER_ID, TENANT_ID);
    assert.equal(result.length, 2);
    assert.equal(result[0]?.cardKey, "accounts");
    assert.equal(result[0]?.available, true);
    assert.equal(result[1]?.cardKey, "loyalty");
    assert.equal(result[1]?.available, false);
    assert.deepEqual(calls[0], {
      fn: "get_customer_portal_dashboard_summary",
      args: { p_auth_user_id: AUTH_USER_ID, p_tenant_id: TENANT_ID },
    });
  });

  test("returns an empty array (never throws) when the RPC returns null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await getCustomerPortalDashboardSummary(client, AUTH_USER_ID, TENANT_ID);
    assert.deepEqual(result, []);
  });

  test("throws CustomerPortalDashboardQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "unexpected: boom" } });
    await assert.rejects(() => getCustomerPortalDashboardSummary(client, AUTH_USER_ID, TENANT_ID), CustomerPortalDashboardQueryError);
  });

  test("preserves a degraded card's own shape (available stays true, degraded flagged)", async () => {
    const degradedRow = { ...ACCOUNTS_ROW, card_key: "tickets", degraded: true, summary: { openTicketCount: 0, openTicketCountCapped: false }, detail_path: "customer-tickets" };
    const { client } = fakeRpcClient({ data: [degradedRow], error: null });
    const result = await getCustomerPortalDashboardSummary(client, AUTH_USER_ID, TENANT_ID);
    assert.equal(result[0]?.degraded, true);
    assert.equal(result[0]?.available, true);
  });
});
