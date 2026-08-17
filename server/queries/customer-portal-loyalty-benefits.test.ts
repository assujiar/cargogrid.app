import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getLoyaltyBenefitEntitlement,
  listLoyaltyBenefitEntitlements,
  listLoyaltyBenefitEntitlementEvents,
  listCustomerPortalLoyaltyBenefitEntitlements,
  LoyaltyBenefitsQueryError,
  type LoyaltyBenefitsQueryClient,
} from "./customer-portal-loyalty-benefits.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ENTITLEMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyBenefitsQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyBenefitsQueryClient;
  return { client, calls };
}

const ENTITLEMENT_ROW = {
  id: ENTITLEMENT_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  benefit_type: "cashback",
  value_amount: 50,
  value_cap: null,
  currency: "USD",
  status: "issued",
  code_hash: null,
  source_type: "manual",
  source_id: null,
  expires_at: null,
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
const EVENT_ROW = {
  id: EVENT_ID,
  tenant_id: TENANT_ID,
  entitlement_id: ENTITLEMENT_ID,
  event_type: "issued",
  amount: 50,
  reason: null,
  actor_auth_user_id: ACTOR_ID,
  actor_label: "manager1",
  created_at: "2026-08-17T00:00:00.000Z",
};

describe("staff reads", () => {
  test("getLoyaltyBenefitEntitlement passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [ENTITLEMENT_ROW], error: null });
    const result = await getLoyaltyBenefitEntitlement(client, TENANT_ID, ENTITLEMENT_ID, ACTOR_ID);
    assert.equal(result.status, "issued");
    assert.deepEqual(calls[0], { fn: "get_loyalty_benefit_entitlement", args: { p_tenant_id: TENANT_ID, p_entitlement_id: ENTITLEMENT_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("getLoyaltyBenefitEntitlement propagates loyalty_benefit_entitlement_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_benefit_entitlement_not_found: x" } });
    await assert.rejects(() => getLoyaltyBenefitEntitlement(client, TENANT_ID, ENTITLEMENT_ID, ACTOR_ID), (err: unknown) => err instanceof LoyaltyBenefitsQueryError && err.code === "loyalty_benefit_entitlement_not_found");
  });

  test("listLoyaltyBenefitEntitlements defaults cursor/limit and filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [ENTITLEMENT_ROW], error: null });
    await listLoyaltyBenefitEntitlements(client, TENANT_ID, ACTOR_ID, { benefitType: "cashback", status: "issued" });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_loyalty_account_id: null,
      p_benefit_type: "cashback",
      p_status: "issued",
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("listLoyaltyBenefitEntitlementEvents filters by entitlementId", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    const rows = await listLoyaltyBenefitEntitlementEvents(client, TENANT_ID, ACTOR_ID, { entitlementId: ENTITLEMENT_ID });
    assert.equal(rows[0]?.eventType, "issued");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_entitlement_id: ENTITLEMENT_ID, p_cursor_created_at: null, p_cursor_id: null, p_limit: 50 });
  });
});

describe("customer-facing reads", () => {
  const CUSTOMER_ROW = {
    id: ENTITLEMENT_ID,
    loyalty_account_id: ACCOUNT_ID,
    program_name: "Cashback Rewards",
    benefit_type: "voucher",
    value_amount: 20,
    value_cap: null,
    currency: "USD",
    status: "issued",
    is_on_hold: false,
    hold_notice: null,
    expires_at: "2026-09-01T00:00:00.000Z",
    record_version: 1,
    created_at: "2026-08-17T00:00:00.000Z",
    updated_at: "2026-08-17T00:00:00.000Z",
  };

  test("listCustomerPortalLoyaltyBenefitEntitlements passes exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [CUSTOMER_ROW], error: null });
    const rows = await listCustomerPortalLoyaltyBenefitEntitlements(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.valueAmount, 20);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_customer_account_id: null, p_benefit_type: null, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 });
  });

  test("deny-by-default: an empty result is not an error", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const rows = await listCustomerPortalLoyaltyBenefitEntitlements(client, TENANT_ID, ACTOR_ID, { customerAccountId: "out-of-scope" });
    assert.deepEqual(rows, []);
  });

  test("a held row never carries an internal-only field even if the raw row somehow had one", async () => {
    const { client } = fakeRpcClient({ data: [{ ...CUSTOMER_ROW, status: "held", is_on_hold: true, hold_notice: "This benefit is temporarily on hold. Contact your account administrator or support for details.", code_hash: "leak-me-not" }], error: null });
    const rows = await listCustomerPortalLoyaltyBenefitEntitlements(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.isOnHold, true);
    assert.equal((rows[0] as unknown as Record<string, unknown>).code_hash, undefined);
  });
});
