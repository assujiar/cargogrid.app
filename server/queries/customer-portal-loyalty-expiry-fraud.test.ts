import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listLoyaltyExpiryRuns,
  getLoyaltyFraudReviewCase,
  listLoyaltyFraudReviewCases,
  listLoyaltyFraudReviewSuppressions,
  listCustomerPortalLoyaltyAccountHoldStatus,
  LoyaltyExpiryFraudQueryError,
  type LoyaltyExpiryFraudQueryClient,
} from "./customer-portal-loyalty-expiry-fraud.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const CASE_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "523e4567-e89b-12d3-a456-426614174000";
const SUPPRESSION_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: LoyaltyExpiryFraudQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LoyaltyExpiryFraudQueryClient;
  return { client, calls };
}

describe("listLoyaltyExpiryRuns", () => {
  test("defaults cursor/limit and maps a completed run", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          job_id: JOB_ID,
          status: "completed",
          run_label: "2026-08-18",
          as_of: "2026-08-18T00:00:00.000Z",
          lots_expired_count: 2,
          entitlements_expired_count: 0,
          error: null,
          created_at: "2026-08-18T00:00:00.000Z",
          completed_at: "2026-08-18T00:00:01.000Z",
          updated_at: "2026-08-18T00:00:01.000Z",
        },
      ],
      error: null,
    });
    const result = await listLoyaltyExpiryRuns(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.lotsExpiredCount, 2);
    assert.deepEqual(calls[0], {
      fn: "list_loyalty_expiry_runs",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_cursor_updated_at: null, p_cursor_id: null, p_limit: 50 },
    });
  });

  test("propagates insufficient_authority with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: x" } });
    await assert.rejects(
      () => listLoyaltyExpiryRuns(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyExpiryFraudQueryError && err.code === "insufficient_authority",
    );
  });
});

describe("getLoyaltyFraudReviewCase / listLoyaltyFraudReviewCases", () => {
  const CASE_ROW = {
    id: CASE_ID,
    tenant_id: TENANT_ID,
    loyalty_account_id: ACCOUNT_ID,
    risk_signal_type: "manual_flag",
    risk_signal_detail: "reported by support",
    status: "open",
    opened_by: "manager1",
    reviewed_by: null,
    review_reason: null,
    decided_at: null,
    idempotency_key: "idem-1",
    record_version: 1,
    created_at: "2026-08-18T00:00:00.000Z",
    updated_at: "2026-08-18T00:00:00.000Z",
  };

  test("getLoyaltyFraudReviewCase passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [CASE_ROW], error: null });
    const result = await getLoyaltyFraudReviewCase(client, TENANT_ID, CASE_ID, ACTOR_ID);
    assert.equal(result.status, "open");
    assert.deepEqual(calls[0], { fn: "get_loyalty_fraud_review_case", args: { p_tenant_id: TENANT_ID, p_case_id: CASE_ID, p_actor_auth_user_id: ACTOR_ID } });
  });

  test("getLoyaltyFraudReviewCase propagates loyalty_fraud_review_case_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "loyalty_fraud_review_case_not_found: x" } });
    await assert.rejects(
      () => getLoyaltyFraudReviewCase(client, TENANT_ID, CASE_ID, ACTOR_ID),
      (err: unknown) => err instanceof LoyaltyExpiryFraudQueryError && err.code === "loyalty_fraud_review_case_not_found",
    );
  });

  test("listLoyaltyFraudReviewCases defaults filters to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [CASE_ROW], error: null });
    await listLoyaltyFraudReviewCases(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_loyalty_account_id: null,
      p_status: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("listLoyaltyFraudReviewCases returns an empty array when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listLoyaltyFraudReviewCases(client, TENANT_ID, ACTOR_ID, { status: "open" });
    assert.deepEqual(result, []);
  });
});

describe("listLoyaltyFraudReviewSuppressions", () => {
  test("defaults activeOnly to false and maps a row", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: SUPPRESSION_ID,
          tenant_id: TENANT_ID,
          loyalty_account_id: ACCOUNT_ID,
          reason: "verified false positive",
          expires_at: "2026-08-25T00:00:00.000Z",
          suppressed_by_auth_user_id: ACTOR_ID,
          suppressed_by: "manager1",
          revoked_at: null,
          revoked_by: null,
          revoked_reason: null,
          record_version: 1,
          created_at: "2026-08-18T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const result = await listLoyaltyFraudReviewSuppressions(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.revokedAt, null);
    assert.deepEqual(calls[0], {
      fn: "list_loyalty_fraud_review_suppressions",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_loyalty_account_id: null, p_active_only: false, p_cursor_created_at: null, p_cursor_id: null, p_limit: 50 },
    });
  });
});

describe("listCustomerPortalLoyaltyAccountHoldStatus", () => {
  test("passes the exact param names, p_customer_account_id optional", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalLoyaltyAccountHoldStatus(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0], {
      fn: "list_customer_portal_loyalty_account_hold_status",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_customer_account_id: null, p_limit: 50 },
    });
  });

  test("returns an empty array (deny-by-default) when data is null", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalLoyaltyAccountHoldStatus(client, TENANT_ID, ACTOR_ID, { customerAccountId: ACCOUNT_ID });
    assert.deepEqual(result, []);
  });

  test("maps a held account row, never exposing internal fraud fields", async () => {
    const { client } = fakeRpcClient({
      data: [{ loyalty_account_id: ACCOUNT_ID, program_name: "Test Program", is_on_hold: true, hold_notice: "Your loyalty account is temporarily on hold. Contact your account administrator or support for details." }],
      error: null,
    });
    const result = await listCustomerPortalLoyaltyAccountHoldStatus(client, TENANT_ID, ACTOR_ID);
    assert.equal(result[0]?.isOnHold, true);
    assert.ok(!("risk_signal_type" in (result[0] as object)));
    assert.ok(!("review_reason" in (result[0] as object)));
  });
});
