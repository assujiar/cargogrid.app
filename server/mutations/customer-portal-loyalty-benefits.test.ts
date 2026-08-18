import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  issueLoyaltyBenefitEntitlement,
  redeemLoyaltyBenefitEntitlement,
  reverseLoyaltyBenefitEntitlement,
  expireLoyaltyBenefitEntitlements,
  holdLoyaltyBenefitEntitlement,
  releaseLoyaltyBenefitEntitlementHold,
  LoyaltyBenefitsMutationError,
  type LoyaltyBenefitsMutationRpcClient,
} from "./customer-portal-loyalty-benefits.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ENTITLEMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyBenefitsMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyBenefitsMutationRpcClient;
  return { client, calls };
}

const ENTITLEMENT_ROW = {
  id: ENTITLEMENT_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  benefit_type: "voucher",
  value_amount: 20,
  value_cap: null,
  currency: "USD",
  status: "issued",
  code_hash: "deadbeef",
  source_type: "manual",
  source_id: null,
  expires_at: "2026-09-01T00:00:00.000Z",
  config_version: 1,
  idempotency_key: "issue-1",
  is_fraud_hold: false,
  hold_reason: null,
  held_by: null,
  held_at: null,
  released_by: null,
  released_at: null,
  record_version: 1,
  created_by: "manager1",
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("issueLoyaltyBenefitEntitlement", () => {
  test("passes exact param names, defaulting valueCap/sourceId/expiresAt/configVersion", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ENTITLEMENT_ROW, raw_code: "CGV-K7M2-QX9B" }], error: null });
    const result = await issueLoyaltyBenefitEntitlement(client, {
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      benefitType: "voucher",
      valueAmount: 20,
      currency: "USD",
      sourceType: "manual",
      idempotencyKey: "issue-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.rawCode, "CGV-K7M2-QX9B");
    assert.deepEqual(calls[0], {
      fn: "issue_loyalty_benefit_entitlement",
      args: {
        p_tenant_id: TENANT_ID,
        p_loyalty_account_id: ACCOUNT_ID,
        p_benefit_type: "voucher",
        p_value_amount: 20,
        p_value_cap: null,
        p_currency: "USD",
        p_source_type: "manual",
        p_source_id: null,
        p_expires_at: null,
        p_idempotency_key: "issue-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "manager1",
        p_config_version: 1,
      },
    });
  });

  test("propagates value_exceeds_cap as a typed error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "value_exceeds_cap: value_amount 100 exceeds value_cap 50" } });
    await assert.rejects(
      () =>
        issueLoyaltyBenefitEntitlement(client, {
          tenantId: TENANT_ID,
          loyaltyAccountId: ACCOUNT_ID,
          benefitType: "cashback",
          valueAmount: 50,
          valueCap: 50,
          currency: "USD",
          sourceType: "manual",
          idempotencyKey: "x",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "manager1",
        }),
      (err: unknown) => err instanceof LoyaltyBenefitsMutationError && err.code === "value_exceeds_cap",
    );
  });

  test("an idempotent replay parses with rawCode null", async () => {
    const { client } = fakeRpcClient({ data: [{ ...ENTITLEMENT_ROW, raw_code: null }], error: null });
    const result = await issueLoyaltyBenefitEntitlement(client, {
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      benefitType: "voucher",
      valueAmount: 20,
      currency: "USD",
      sourceType: "manual",
      idempotencyKey: "issue-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.rawCode, null);
  });
});

describe("redeemLoyaltyBenefitEntitlement", () => {
  test("passes exact param names with a bare code and null expectedVersion", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ENTITLEMENT_ROW, status: "redeemed" }], error: null });
    const result = await redeemLoyaltyBenefitEntitlement(client, { tenantId: TENANT_ID, entitlementIdOrCode: "CGV-K7M2-QX9B", actorAuthUserId: ACTOR_ID, actorLabel: "customer-alpha" });
    assert.equal(result.status, "redeemed");
    assert.deepEqual(calls[0], {
      fn: "redeem_loyalty_benefit_entitlement",
      args: { p_tenant_id: TENANT_ID, p_entitlement_id_or_code: "CGV-K7M2-QX9B", p_expected_version: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "customer-alpha" },
    });
  });

  test("passes a real expectedVersion when supplied (e.g. the wallet's own per-row redeem button)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ENTITLEMENT_ROW, status: "redeemed" }], error: null });
    await redeemLoyaltyBenefitEntitlement(client, { tenantId: TENANT_ID, entitlementIdOrCode: ENTITLEMENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "customer-alpha" });
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });

  test("propagates voucher_redemption_failed as a typed error -- the anti-enumerating collapse", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "voucher_redemption_failed: this voucher code cannot be redeemed" } });
    await assert.rejects(
      () => redeemLoyaltyBenefitEntitlement(client, { tenantId: TENANT_ID, entitlementIdOrCode: "CGV-ZZZZ-ZZZZ", actorAuthUserId: ACTOR_ID, actorLabel: "customer-alpha" }),
      (err: unknown) => err instanceof LoyaltyBenefitsMutationError && err.code === "voucher_redemption_failed",
    );
  });
});

describe("reverseLoyaltyBenefitEntitlement / expireLoyaltyBenefitEntitlements", () => {
  test("reverseLoyaltyBenefitEntitlement passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ENTITLEMENT_ROW, status: "reversed" }], error: null });
    const result = await reverseLoyaltyBenefitEntitlement(client, { tenantId: TENANT_ID, entitlementId: ENTITLEMENT_ID, expectedVersion: 1, reason: "invoice cancelled", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.status, "reversed");
    assert.deepEqual(calls[0], {
      fn: "reverse_loyalty_benefit_entitlement",
      args: { p_tenant_id: TENANT_ID, p_entitlement_id: ENTITLEMENT_ID, p_expected_version: 1, p_reason: "invoice cancelled", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" },
    });
  });

  test("expireLoyaltyBenefitEntitlements returns an array, even a zero-row result", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await expireLoyaltyBenefitEntitlements(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.deepEqual(result, []);
  });
});

describe("holdLoyaltyBenefitEntitlement / releaseLoyaltyBenefitEntitlementHold", () => {
  test("holdLoyaltyBenefitEntitlement passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ENTITLEMENT_ROW, status: "held", is_fraud_hold: true, hold_reason: "suspected fraud" }], error: null });
    const result = await holdLoyaltyBenefitEntitlement(client, { tenantId: TENANT_ID, entitlementId: ENTITLEMENT_ID, reason: "suspected fraud", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(result.status, "held");
    assert.deepEqual(calls[0], { fn: "hold_loyalty_benefit_entitlement", args: { p_tenant_id: TENANT_ID, p_entitlement_id: ENTITLEMENT_ID, p_reason: "suspected fraud", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "manager1" } });
  });

  test("releaseLoyaltyBenefitEntitlementHold propagates entitlement_not_held as a typed error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "entitlement_not_held: entitlement x is issued -- not currently on hold" } });
    await assert.rejects(
      () => releaseLoyaltyBenefitEntitlementHold(client, { tenantId: TENANT_ID, entitlementId: ENTITLEMENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
      (err: unknown) => err instanceof LoyaltyBenefitsMutationError && err.code === "entitlement_not_held",
    );
  });
});
