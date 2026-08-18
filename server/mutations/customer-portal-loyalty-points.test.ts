import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  postLoyaltyPointsEarned,
  reverseLoyaltyPointsEarned,
  expireLoyaltyPointLots,
  consumeLoyaltyPointsFifo,
  requestLoyaltyPointAdjustment,
  decideLoyaltyPointAdjustment,
  LoyaltyPointsMutationError,
  type LoyaltyPointsMutationRpcClient,
} from "./customer-portal-loyalty-points.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LOT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENTRY_ID = "423e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyPointsMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyPointsMutationRpcClient;
  return { client, calls };
}

const ENTRY_ROW = {
  id: ENTRY_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  event_type: "earn",
  amount: 100,
  lot_id: LOT_ID,
  source_type: "loyalty_earning_event",
  source_id: EVENT_ID,
  idempotency_key: "earning-event:" + EVENT_ID,
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
  reason: "internal note",
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

describe("postLoyaltyPointsEarned / reverseLoyaltyPointsEarned / expireLoyaltyPointLots", () => {
  test("postLoyaltyPointsEarned passes exact param names, defaulting expiryDays", async () => {
    const { client, calls } = fakeRpcClient({ data: [ENTRY_ROW], error: null });
    const result = await postLoyaltyPointsEarned(client, { tenantId: TENANT_ID, earningEventId: EVENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.eventType, "earn");
    assert.deepEqual(calls[0], { fn: "post_loyalty_points_earned", args: { p_tenant_id: TENANT_ID, p_earning_event_id: EVENT_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1", p_expiry_days: 365 } });
  });

  test("postLoyaltyPointsEarned propagates a typed error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "earning_event_is_a_reversal: x" } });
    await assert.rejects(
      () => postLoyaltyPointsEarned(client, { tenantId: TENANT_ID, earningEventId: EVENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
      (err: unknown) => err instanceof LoyaltyPointsMutationError && err.code === "earning_event_is_a_reversal",
    );
  });

  test("reverseLoyaltyPointsEarned passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ENTRY_ROW, event_type: "reversal", amount: -100, corrects_entry_id: ENTRY_ID }], error: null });
    const result = await reverseLoyaltyPointsEarned(client, { tenantId: TENANT_ID, reversalEarningEventId: EVENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.eventType, "reversal");
    assert.equal(result.correctsEntryId, ENTRY_ID);
    assert.deepEqual(calls[0], { fn: "reverse_loyalty_points_earned", args: { p_tenant_id: TENANT_ID, p_reversal_earning_event_id: EVENT_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" } });
  });

  test("expireLoyaltyPointLots returns an array, even a zero-row result", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await expireLoyaltyPointLots(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.deepEqual(result, []);
  });
});

describe("consumeLoyaltyPointsFifo", () => {
  test("passes exact param names and parses every returned per-lot entry", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        { ...ENTRY_ROW, event_type: "redemption", amount: -60, source_type: "redemption", source_id: "923e4567-e89b-12d3-a456-426614174000", idempotency_key: "redeem-1:lot:" + LOT_ID },
        { ...ENTRY_ROW, id: "823e4567-e89b-12d3-a456-426614174000", event_type: "redemption", amount: -40, source_type: "redemption", source_id: "923e4567-e89b-12d3-a456-426614174000", idempotency_key: "redeem-1:lot:other" },
      ],
      error: null,
    });
    const result = await consumeLoyaltyPointsFifo(client, {
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      amount: 100,
      sourceType: "redemption",
      sourceId: "src-1",
      idempotencyKey: "redeem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.length, 2);
    assert.equal(result[0]?.amount, -60);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_loyalty_account_id: ACCOUNT_ID,
      p_amount: 100,
      p_source_type: "redemption",
      p_source_id: "src-1",
      p_idempotency_key: "redeem-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "manager1",
    });
  });

  test("propagates insufficient_points_balance as a typed error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_points_balance: 40 short" } });
    await assert.rejects(
      () => consumeLoyaltyPointsFifo(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, amount: 999, sourceType: "redemption", sourceId: "src-2", idempotencyKey: "redeem-2", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
      (err: unknown) => err instanceof LoyaltyPointsMutationError && err.code === "insufficient_points_balance",
    );
  });
});

describe("requestLoyaltyPointAdjustment / decideLoyaltyPointAdjustment (maker-checker)", () => {
  test("requestLoyaltyPointAdjustment passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [REQUEST_ROW], error: null });
    const result = await requestLoyaltyPointAdjustment(client, { tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, adjustmentAmount: 50, reason: "internal note", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.status, "pending_approval");
    assert.deepEqual(calls[0], {
      fn: "request_loyalty_point_adjustment",
      args: { p_tenant_id: TENANT_ID, p_loyalty_account_id: ACCOUNT_ID, p_adjustment_amount: 50, p_reason: "internal note", p_idempotency_key: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });

  test("decideLoyaltyPointAdjustment propagates self_approval_not_allowed as a typed error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_allowed: cannot decide your own request" } });
    await assert.rejects(
      () => decideLoyaltyPointAdjustment(client, { tenantId: TENANT_ID, adjustmentId: REQUEST_ID, expectedVersion: 1, decision: "approved", decisionNotes: "approving my own", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
      (err: unknown) => err instanceof LoyaltyPointsMutationError && err.code === "self_approval_not_allowed",
    );
  });

  test("decideLoyaltyPointAdjustment approved passes exact param names and returns a real ledger_entry_id", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...REQUEST_ROW, status: "approved", decided_by_auth_user_id: "823e4567-e89b-12d3-a456-426614174999", decided_by: "manager2", decided_at: "2026-08-17T01:00:00.000Z", decision_notes: "confirmed", ledger_entry_id: ENTRY_ID }], error: null });
    const result = await decideLoyaltyPointAdjustment(client, { tenantId: TENANT_ID, adjustmentId: REQUEST_ID, expectedVersion: 1, decision: "approved", decisionNotes: "confirmed", actorAuthUserId: ACTOR_ID, actorLabel: "manager2" });
    assert.equal(result.status, "approved");
    assert.equal(result.ledgerEntryId, ENTRY_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_adjustment_id: REQUEST_ID, p_expected_version: 1, p_decision: "approved", p_decision_notes: "confirmed", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager2" });
  });
});
