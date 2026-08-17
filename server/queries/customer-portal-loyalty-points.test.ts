import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getLoyaltyPointBalance,
  listLoyaltyPointBalances,
  getLoyaltyPointLot,
  listLoyaltyPointLots,
  listLoyaltyPointLedgerEntries,
  getLoyaltyPointAdjustmentRequest,
  listLoyaltyPointAdjustmentRequests,
  listCustomerPortalLoyaltyPointBalances,
  listCustomerPortalLoyaltyPointLedgerEntries,
  listCustomerPortalLoyaltyPointExpirySchedule,
  LoyaltyPointsQueryError,
  type LoyaltyPointsQueryClient,
} from "./customer-portal-loyalty-points.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LOT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENTRY_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyPointsQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyPointsQueryClient;
  return { client, calls };
}

const BALANCE_ROW = { id: LOT_ID, tenant_id: TENANT_ID, loyalty_account_id: ACCOUNT_ID, total_earned: 100, total_consumed: 0, available: 100, record_version: 1, updated_at: "2026-08-17T00:00:00.000Z" };
const LOT_ROW = {
  id: LOT_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  source_earning_event_id: ENTRY_ID,
  original_amount: 100,
  remaining_amount: 100,
  expires_at: "2026-09-01T00:00:00.000Z",
  status: "active",
  record_version: 1,
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};
const ENTRY_ROW = {
  id: ENTRY_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  event_type: "earn",
  amount: 100,
  lot_id: LOT_ID,
  source_type: "loyalty_earning_event",
  source_id: ENTRY_ID,
  idempotency_key: "earning-event:" + ENTRY_ID,
  corrects_entry_id: null,
  reason: null,
  config_version: 1,
  created_by: "manager1",
  created_at: "2026-08-17T00:00:00.000Z",
};
const REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  adjustment_amount: 50,
  reason: "note",
  requested_by_auth_user_id: ACTOR_ID,
  requested_by: "manager1",
  requested_at: "2026-08-17T00:00:00.000Z",
  status: "pending_approval",
  decided_by_auth_user_id: null,
  decided_by: null,
  decided_at: null,
  decision_notes: null,
  ledger_entry_id: null,
  idempotency_key: "adj-req-1",
  record_version: 1,
  created_by: "manager1",
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("staff reads", () => {
  test("getLoyaltyPointBalance passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [BALANCE_ROW], error: null });
    const result = await getLoyaltyPointBalance(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID);
    assert.equal(result.available, 100);
    assert.deepEqual(calls[0], { fn: "get_loyalty_point_balance", args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("getLoyaltyPointBalance propagates loyalty_point_balance_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_point_balance_not_found: x" } });
    await assert.rejects(() => getLoyaltyPointBalance(client, TENANT_ID, ACCOUNT_ID, ACTOR_ID), (err: unknown) => err instanceof LoyaltyPointsQueryError && err.code === "loyalty_point_balance_not_found");
  });

  test("listLoyaltyPointBalances defaults cursor/limit", async () => {
    const { client, calls } = fakeRpcClient({ data: [BALANCE_ROW], error: null });
    await listLoyaltyPointBalances(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 });
  });

  test("getLoyaltyPointLot / listLoyaltyPointLots", async () => {
    const { client, calls } = fakeRpcClient({ data: [LOT_ROW], error: null });
    const lot = await getLoyaltyPointLot(client, TENANT_ID, LOT_ID, ACTOR_ID);
    assert.equal(lot.status, "active");
    await listLoyaltyPointLots(client, TENANT_ID, ACTOR_ID, { loyaltyAccountId: ACCOUNT_ID, status: "active" });
    assert.deepEqual(calls[1]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_loyalty_account_id: ACCOUNT_ID, p_status: "active", p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 });
  });

  test("listLoyaltyPointLedgerEntries filters by eventType", async () => {
    const { client, calls } = fakeRpcClient({ data: [ENTRY_ROW], error: null });
    const rows = await listLoyaltyPointLedgerEntries(client, TENANT_ID, ACTOR_ID, { eventType: "earn" });
    assert.equal(rows[0]?.eventType, "earn");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_loyalty_account_id: null, p_event_type: "earn", p_cursor_created_at: null, p_cursor_id: null, p_limit: 50 });
  });

  test("getLoyaltyPointAdjustmentRequest / listLoyaltyPointAdjustmentRequests", async () => {
    const { client } = fakeRpcClient({ data: [REQUEST_ROW], error: null });
    const request = await getLoyaltyPointAdjustmentRequest(client, TENANT_ID, REQUEST_ID, ACTOR_ID);
    assert.equal(request.status, "pending_approval");
    const rows = await listLoyaltyPointAdjustmentRequests(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
  });
});

describe("customer-facing reads", () => {
  const CUSTOMER_BALANCE_ROW = { loyalty_account_id: ACCOUNT_ID, customer_account_id: CUSTOMER_ACCOUNT_ID, program_id: PROGRAM_ID, program_name: "Points Rewards", total_earned: 100, total_consumed: 0, available: 100, updated_at: "2026-08-17T00:00:00.000Z" };
  const CUSTOMER_ENTRY_ROW = { id: ENTRY_ID, program_name: "Points Rewards", event_type: "earn", amount: 100, description: "Points earned", created_at: "2026-08-17T00:00:00.000Z" };
  const CUSTOMER_SCHEDULE_ROW = { id: LOT_ID, program_name: "Points Rewards", remaining_amount: 100, expires_at: "2026-09-01T00:00:00.000Z" };

  test("listCustomerPortalLoyaltyPointBalances", async () => {
    const { client, calls } = fakeRpcClient({ data: [CUSTOMER_BALANCE_ROW], error: null });
    const rows = await listCustomerPortalLoyaltyPointBalances(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.available, 100);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_customer_account_id: null, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 });
  });

  test("listCustomerPortalLoyaltyPointLedgerEntries never carries a reason field even if present on the raw row", async () => {
    const { client } = fakeRpcClient({ data: [{ ...CUSTOMER_ENTRY_ROW, reason: "internal note" }], error: null });
    const rows = await listCustomerPortalLoyaltyPointLedgerEntries(client, TENANT_ID, ACTOR_ID);
    assert.equal((rows[0] as unknown as Record<string, unknown>).reason, undefined);
    assert.equal(rows[0]?.description, "Points earned");
  });

  test("listCustomerPortalLoyaltyPointExpirySchedule passes ascending cursor param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [CUSTOMER_SCHEDULE_ROW], error: null });
    await listCustomerPortalLoyaltyPointExpirySchedule(client, TENANT_ID, ACTOR_ID, { cursorExpiresAt: "2026-08-20T00:00:00.000Z", cursorId: LOT_ID });
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_customer_account_id: null, p_cursor_expires_at: "2026-08-20T00:00:00.000Z", p_cursor_id: LOT_ID, p_limit: 50 });
  });

  test("deny-by-default: an empty result is not an error", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const rows = await listCustomerPortalLoyaltyPointBalances(client, TENANT_ID, ACTOR_ID, { customerAccountId: "out-of-scope" });
    assert.deepEqual(rows, []);
  });
});
