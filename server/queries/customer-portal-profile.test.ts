import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getCustomerPortalAccountProfile,
  listCustomerPortalAccountContacts,
  listCustomerPortalProfileChangeRequests,
  CustomerPortalProfileQueryError,
  type CustomerPortalProfileQueryClient,
} from "./customer-portal-profile.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalProfileQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalProfileQueryClient;
  return { client, calls };
}

const PROFILE_ROW = {
  account_id: ACCOUNT_ID,
  legal_name: "Cpp1 Account Alpha Pte Ltd",
  trade_name: "Alpha Logistics",
  tax_id: "01.111.222.3-000.000",
  billing_address: { line1: "Jl. Alpha 1", city: "Jakarta", country: "ID" },
  customer_status: "active",
  record_version: 3,
  updated_at: "2026-08-17T00:00:00.000Z",
  pending_change_request_count: 1,
  latest_pending_change_request_id: REQUEST_ID,
  latest_pending_change_request_field: "trade_name",
  latest_pending_change_request_submitted_at: "2026-08-17T00:00:00.000Z",
};

describe("getCustomerPortalAccountProfile", () => {
  test("maps the RPC's own single row and passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [PROFILE_ROW], error: null });
    const result = await getCustomerPortalAccountProfile(client, TENANT_ID, ACTOR_ID, ACCOUNT_ID);
    assert.equal(result.legalName, "Cpp1 Account Alpha Pte Ltd");
    assert.equal(result.pendingChangeRequestCount, 1);
    assert.deepEqual(calls[0], {
      fn: "get_customer_portal_account_profile",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_account_id: ACCOUNT_ID },
    });
  });

  test("propagates record_not_found with .code set (anti-enumerating -- not-found and forbidden are indistinguishable)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted account exists for x" } });
    await assert.rejects(
      () => getCustomerPortalAccountProfile(client, TENANT_ID, ACTOR_ID, ACCOUNT_ID),
      (error: unknown) => error instanceof CustomerPortalProfileQueryError && error.code === "record_not_found",
    );
  });
});

describe("listCustomerPortalAccountContacts", () => {
  test("maps every returned contact row, camelCased", async () => {
    const { client, calls } = fakeRpcClient({
      data: [{ contact_id: "623e4567-e89b-12d3-a456-426614174000", full_name: "Jane Requester", title: "Ops Manager", email: "jane@test.com", phone: "0811", role: "primary", is_primary: true }],
      error: null,
    });
    const result = await listCustomerPortalAccountContacts(client, TENANT_ID, ACTOR_ID, ACCOUNT_ID);
    assert.equal(result.length, 1);
    assert.equal(result[0]!.fullName, "Jane Requester");
    assert.deepEqual(calls[0]!.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_account_id: ACCOUNT_ID });
  });

  test("returns an empty array (never throws) when the RPC returns no rows", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalAccountContacts(client, TENANT_ID, ACTOR_ID, ACCOUNT_ID);
    assert.deepEqual(result, []);
  });
});

describe("listCustomerPortalProfileChangeRequests", () => {
  test("passes default pagination and filters through as explicit null, never undefined", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalProfileChangeRequests(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(calls[0]!.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: null,
      p_status: null,
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("forwards accountId/status filters and cursor options", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalProfileChangeRequests(client, TENANT_ID, ACTOR_ID, { accountId: ACCOUNT_ID, status: "pending", cursorUpdatedAt: "2026-08-17T00:00:00.000Z", cursorId: REQUEST_ID, limit: 25 });
    assert.deepEqual(calls[0]!.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_account_id: ACCOUNT_ID,
      p_status: "pending",
      p_cursor_updated_at: "2026-08-17T00:00:00.000Z",
      p_cursor_id: REQUEST_ID,
      p_limit: 25,
    });
  });
});
