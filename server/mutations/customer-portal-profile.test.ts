import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  submitCustomerProfileChangeRequest,
  withdrawCustomerProfileChangeRequest,
  decideCustomerProfileChangeRequest,
  CustomerPortalProfileMutationError,
  type CustomerPortalProfileMutationRpcClient,
} from "./customer-portal-profile.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_actor_auth_user_id: ACTOR_ID,
  field_name: "trade_name",
  proposed_value: "Alpha Logistics Group",
  status: "pending",
  reviewed_by: null,
  reviewed_at: null,
  review_reason: null,
  idempotency_key: "submit-1",
  record_version: 1,
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalProfileMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalProfileMutationRpcClient;
  return { client, calls };
}

describe("submitCustomerProfileChangeRequest", () => {
  test("passes the exact param names for a trade_name proposal", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    const result = await submitCustomerProfileChangeRequest(client, {
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      fieldName: "trade_name",
      proposedValue: "Alpha Logistics Group",
      idempotencyKey: "submit-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.status, "pending");
    assert.deepEqual(calls[0], {
      fn: "submit_customer_profile_change_request",
      args: {
        p_tenant_id: TENANT_ID,
        p_account_id: ACCOUNT_ID,
        p_field_name: "trade_name",
        p_proposed_value: "Alpha Logistics Group",
        p_idempotency_key: "submit-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("rejects a forbidden field name at the Zod boundary, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: [ROW], error: null });
    await assert.rejects(() =>
      submitCustomerProfileChangeRequest(client, {
        tenantId: TENANT_ID,
        accountId: ACCOUNT_ID,
        // @ts-expect-error -- deliberately an out-of-registry field for this test
        fieldName: "legal_name",
        proposedValue: "Forged Legal Name",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "alpha-admin",
      }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies account_not_available", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "account_not_available: x is not an account this identity may propose a profile change for" } });
    await assert.rejects(
      () => submitCustomerProfileChangeRequest(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, fieldName: "trade_name", proposedValue: "x", actorAuthUserId: ACTOR_ID, actorLabel: "beta-admin" }),
      (error: unknown) => error instanceof CustomerPortalProfileMutationError && error.code === "account_not_available",
    );
  });
});

describe("withdrawCustomerProfileChangeRequest", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "withdrawn" }], error: null });
    const result = await withdrawCustomerProfileChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "alpha-member" });
    assert.equal(result.status, "withdrawn");
    assert.deepEqual(calls[0], {
      fn: "withdraw_customer_profile_change_request",
      args: { p_request_id: REQUEST_ID, p_expected_version: 1, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "alpha-member" },
    });
  });

  test("classifies invalid_transition for an already-terminal request", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: profile change request x is approved and can no longer be withdrawn" } });
    await assert.rejects(
      () => withdrawCustomerProfileChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" }),
      (error: unknown) => error instanceof CustomerPortalProfileMutationError && error.code === "invalid_transition",
    );
  });
});

describe("decideCustomerProfileChangeRequest", () => {
  test("passes the exact param names for an approve decision", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ROW, status: "approved", reviewed_by: "staff", reviewed_at: "2026-08-17T01:00:00.000Z", review_reason: "verified" }], error: null });
    const result = await decideCustomerProfileChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, decision: "approve", reviewReason: "verified", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(result.status, "approved");
    assert.deepEqual(calls[0], {
      fn: "decide_customer_profile_change_request",
      args: { p_request_id: REQUEST_ID, p_expected_version: 1, p_decision: "approve", p_review_reason: "verified", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff" },
    });
  });

  test("classifies insufficient_authority for a non-staff caller", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks COM:Approve (no_granting_role) for tenant y" } });
    await assert.rejects(
      () => decideCustomerProfileChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, decision: "approve", reviewReason: "self-serve attempt", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" }),
      (error: unknown) => error instanceof CustomerPortalProfileMutationError && error.code === "insufficient_authority",
    );
  });

  test("classifies self_approval_not_permitted", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_permitted: an actor may not decide their own profile change request" } });
    await assert.rejects(
      () => decideCustomerProfileChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, decision: "approve", reviewReason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof CustomerPortalProfileMutationError && error.code === "self_approval_not_permitted",
    );
  });
});
