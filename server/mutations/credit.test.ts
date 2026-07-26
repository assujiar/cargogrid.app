import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  requestCustomerCreditProfile,
  decideCreditProfileApprovalStep,
  holdCreditProfile,
  createCreditOverride,
  checkCustomerCredit,
  CreditMutationError,
  type CreditMutationRpcClient,
} from "./credit.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROFILE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "623e4567-e89b-12d3-a456-426614174000";

const PROFILE_ROW = {
  id: PROFILE_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  currency: "IDR",
  requested_limit_amount: 50000000,
  approved_limit_amount: null,
  status: "requested",
  effective_from: null,
  effective_to: null,
  hold_reason: null,
  rejected_reason: null,
  approval_request_id: "723e4567-e89b-12d3-a456-426614174000",
  supersedes_profile_id: null,
  approved_by: null,
  approved_at: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): CreditMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CreditMutationRpcClient;
}

describe("requestCustomerCreditProfile", () => {
  test("calls request_customer_credit_profile with exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: PROFILE_ROW, error: null }, calls);
    const profile = await requestCustomerCreditProfile(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, currency: "IDR", requestedLimitAmount: 50000000, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "request_customer_credit_profile");
    assert.equal(calls[0]?.args.p_requested_limit_amount, 50000000);
    assert.equal(profile.status, "requested");
  });

  test("classifies credit_profile_already_requested", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "credit_profile_already_requested: account x already has a live credit profile" } }, []);
    await assert.rejects(
      () => requestCustomerCreditProfile(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, currency: "IDR", requestedLimitAmount: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof CreditMutationError);
        assert.equal(err.code, "credit_profile_already_requested");
        return true;
      },
    );
  });
});

describe("decideCreditProfileApprovalStep", () => {
  test("classifies reauth_required", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "reauth_required: re-authentication must have completed within the last 5 minutes" } }, []);
    await assert.rejects(
      () => decideCreditProfileApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", reauthConfirmedAt: "2026-07-24T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "approver" }),
      (err: unknown) => {
        assert.ok(err instanceof CreditMutationError);
        assert.equal(err.code, "reauth_required");
        return true;
      },
    );
  });

  test("passes the reauth timestamp through as p_reauth_confirmed_at", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...PROFILE_ROW, status: "active", approved_limit_amount: 50000000 }, error: null }, calls);
    await decideCreditProfileApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", reauthConfirmedAt: "2026-07-24T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.args.p_reauth_confirmed_at, "2026-07-24T00:00:00.000Z");
  });
});

describe("holdCreditProfile", () => {
  test("classifies insufficient_authority", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks COM:Approve (missing) for tenant y" } }, []);
    await assert.rejects(
      () => holdCreditProfile(client, { profileId: PROFILE_ID, expectedVersion: 2, reason: "Overdue", reauthConfirmedAt: "2026-07-24T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof CreditMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("createCreditOverride", () => {
  test("classifies invalid_expiry", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "invalid_expiry: a credit override must expire in the future" } }, []);
    await assert.rejects(
      () =>
        createCreditOverride(client, { profileId: PROFILE_ID, amount: 100, reason: "x", expiresAt: "2020-01-01T00:00:00.000Z", reauthConfirmedAt: "2026-07-24T00:00:00.000Z", actorAuthUserId: ACTOR_ID, actorLabel: "approver" }),
      (err: unknown) => {
        assert.ok(err instanceof CreditMutationError);
        assert.equal(err.code, "invalid_expiry");
        return true;
      },
    );
  });
});

describe("checkCustomerCredit", () => {
  test("parses the RPC's own masked/unmasked result row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient(
      {
        data: [
          {
            id: "823e4567-e89b-12d3-a456-426614174000",
            credit_profile_id: PROFILE_ID,
            profile_status_at_check: "active",
            currency: "IDR",
            requested_amount: 30000000,
            effective_limit_amount: 50000000,
            amount_masked: false,
            outcome: "allow",
            checked_at: "2026-07-24T00:00:00.000Z",
          },
        ],
        error: null,
      },
      calls,
    );
    const result = await checkCustomerCredit(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, currency: "IDR", requestedAmount: 30000000, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.fn, "check_customer_credit");
    assert.equal(result.outcome, "allow");
  });

  test("throws when the RPC returns no row", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    await assert.rejects(() => checkCustomerCredit(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, currency: "IDR", requestedAmount: 1, actorAuthUserId: ACTOR_ID, actorLabel: "approver" }));
  });
});
