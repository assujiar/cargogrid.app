import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  submitCustomerContactChangeRequest,
  withdrawCustomerContactChangeRequest,
  decideCustomerContactChangeRequest,
  CustomerPortalContactChangeMutationError,
  type CustomerPortalContactChangeMutationRpcClient,
} from "./customer-portal-contact-change.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const CONTACT_ID = "623e4567-e89b-12d3-a456-426614174000";

const ADD_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  requested_by_actor_auth_user_id: ACTOR_ID,
  change_kind: "add",
  target_contact_id: null,
  full_name: "Jane Doe",
  title: null,
  email: "jane@test.com",
  phone: null,
  role: "primary",
  is_primary: true,
  status: "pending",
  reviewed_by: null,
  reviewed_at: null,
  review_reason: null,
  idempotency_key: "submit-1",
  record_version: 1,
  created_at: "2026-09-01T00:00:00.000Z",
  updated_at: "2026-09-01T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalContactChangeMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalContactChangeMutationRpcClient;
  return { client, calls };
}

describe("submitCustomerContactChangeRequest", () => {
  test("passes the exact param names for an add request", async () => {
    const { client, calls } = fakeRpcClient({ data: [ADD_ROW], error: null });
    const result = await submitCustomerContactChangeRequest(client, {
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      changeKind: "add",
      fullName: "Jane Doe",
      email: "jane@test.com",
      role: "primary",
      isPrimary: true,
      idempotencyKey: "submit-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.equal(result.status, "pending");
    assert.deepEqual(calls[0], {
      fn: "submit_customer_contact_change_request",
      args: {
        p_tenant_id: TENANT_ID,
        p_account_id: ACCOUNT_ID,
        p_change_kind: "add",
        p_target_contact_id: null,
        p_full_name: "Jane Doe",
        p_title: null,
        p_email: "jane@test.com",
        p_phone: null,
        p_role: "primary",
        p_is_primary: true,
        p_idempotency_key: "submit-1",
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("rejects an add request supplying a targetContactId at the Zod boundary, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: [ADD_ROW], error: null });
    await assert.rejects(() =>
      submitCustomerContactChangeRequest(client, {
        tenantId: TENANT_ID,
        accountId: ACCOUNT_ID,
        changeKind: "add",
        targetContactId: CONTACT_ID,
        fullName: "Jane Doe",
        email: "jane@test.com",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "alpha-admin",
      }),
    );
    assert.equal(calls.length, 0);
  });

  test("passes the exact param names for a remove request", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ADD_ROW, change_kind: "remove", target_contact_id: CONTACT_ID, full_name: null, email: null, role: null, is_primary: null }], error: null });
    await submitCustomerContactChangeRequest(client, {
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      changeKind: "remove",
      targetContactId: CONTACT_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "alpha-admin",
    });
    assert.deepEqual(calls[0], {
      fn: "submit_customer_contact_change_request",
      args: {
        p_tenant_id: TENANT_ID,
        p_account_id: ACCOUNT_ID,
        p_change_kind: "remove",
        p_target_contact_id: CONTACT_ID,
        p_full_name: null,
        p_title: null,
        p_email: null,
        p_phone: null,
        p_role: null,
        p_is_primary: null,
        p_idempotency_key: null,
        p_actor_auth_user_id: ACTOR_ID,
        p_actor_label: "alpha-admin",
      },
    });
  });

  test("classifies contact_not_available", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "contact_not_available: x is not a contact linked to this account" } });
    await assert.rejects(
      () => submitCustomerContactChangeRequest(client, { tenantId: TENANT_ID, accountId: ACCOUNT_ID, changeKind: "update", targetContactId: CONTACT_ID, title: "X", actorAuthUserId: ACTOR_ID, actorLabel: "alpha-admin" }),
      (error: unknown) => error instanceof CustomerPortalContactChangeMutationError && error.code === "contact_not_available",
    );
  });
});

describe("withdrawCustomerContactChangeRequest", () => {
  test("passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ADD_ROW, status: "withdrawn" }], error: null });
    const result = await withdrawCustomerContactChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "alpha-member" });
    assert.equal(result.status, "withdrawn");
    assert.deepEqual(calls[0], {
      fn: "withdraw_customer_contact_change_request",
      args: { p_request_id: REQUEST_ID, p_expected_version: 1, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "alpha-member" },
    });
  });
});

describe("decideCustomerContactChangeRequest", () => {
  test("passes the exact param names for an approve decision", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ADD_ROW, status: "approved", reviewed_by: "staff", reviewed_at: "2026-09-01T01:00:00.000Z", review_reason: "verified" }], error: null });
    const result = await decideCustomerContactChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, decision: "approve", reviewReason: "verified", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });
    assert.equal(result.status, "approved");
    assert.deepEqual(calls[0], {
      fn: "decide_customer_contact_change_request",
      args: { p_request_id: REQUEST_ID, p_expected_version: 1, p_decision: "approve", p_review_reason: "verified", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "staff" },
    });
  });

  test("classifies contact_link_conflict", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "contact_link_conflict: this role change would collide with an existing link for the same contact and account" } });
    await assert.rejects(
      () => decideCustomerContactChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, decision: "approve", reviewReason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof CustomerPortalContactChangeMutationError && error.code === "contact_link_conflict",
    );
  });

  test("classifies self_approval_not_permitted", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_permitted: an actor may not decide their own contact change request" } });
    await assert.rejects(
      () => decideCustomerContactChangeRequest(client, { requestId: REQUEST_ID, expectedVersion: 1, decision: "approve", reviewReason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (error: unknown) => error instanceof CustomerPortalContactChangeMutationError && error.code === "self_approval_not_permitted",
    );
  });
});
