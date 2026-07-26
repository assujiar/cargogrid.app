import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listCreditProfiles, getCreditProfileForAccount, getCreditProfileById, listCreditProfileOverrides, getCreditProfileApprovalOverview, listCreditProfileApprovalInboxForActor, CreditQueryError, type CreditQueryClient } from "./credit.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROFILE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "723e4567-e89b-12d3-a456-426614174000";

const PROFILE_ROW = {
  id: PROFILE_ID,
  tenant_id: TENANT_ID,
  account_id: ACCOUNT_ID,
  currency: "IDR",
  requested_limit_amount: 50000000,
  approved_limit_amount: 50000000,
  amount_masked: false,
  status: "active",
  effective_from: "2026-07-24T00:00:00.000Z",
  effective_to: null,
  hold_reason: null,
  rejected_reason: null,
  approval_request_id: REQUEST_ID,
  supersedes_profile_id: null,
  approved_by: "approver",
  approved_at: "2026-07-24T00:00:00.000Z",
  record_version: 2,
  created_by: "rep",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeClient(opts: {
  tableResponse?: { data: unknown; error: { message: string } | null };
  rpcResponse?: { data: unknown; error: { message: string } | null };
  approvalRequestsResponse?: { data: unknown; error: { message: string } | null };
}): CreditQueryClient & { calls: { table: string[]; rpc: { fn: string; args: Record<string, unknown> }[]; eqCalls: { column: string; value: unknown }[] } } {
  const calls = { table: [] as string[], rpc: [] as { fn: string; args: Record<string, unknown> }[], eqCalls: [] as { column: string; value: unknown }[] };
  const fake = {
    calls,
    from(table: string) {
      calls.table.push(table);
      if (table === "approval_requests") {
        const response = opts.approvalRequestsResponse ?? { data: [], error: null };
        return { select: () => ({ in: async () => response }) };
      }
      const response = opts.tableResponse ?? { data: [], error: null };
      const chain = {
        eq(column: string, value: unknown) {
          calls.eqCalls.push({ column, value });
          return chain;
        },
        order: () => chain,
        limit: () => chain,
        maybeSingle: async () => ({ data: Array.isArray(response.data) ? (response.data[0] ?? null) : response.data, error: response.error }),
        // Thenable, mirroring Supabase's own query builder -- resolves to the response at
        // whichever point in the chain the caller awaits it (after .order() alone, or
        // after .order().limit()).
        then(resolve: (value: typeof response) => void) {
          resolve(response);
        },
      };
      return { select: () => chain };
    },
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.rpc.push({ fn, args });
      return opts.rpcResponse ?? { data: [], error: null };
    },
  };
  return fake as unknown as CreditQueryClient & { calls: typeof calls };
}

describe("listCreditProfiles", () => {
  test("reads from credit_profiles_directory filtered by tenant_id, newest first", async () => {
    const client = fakeClient({ tableResponse: { data: [PROFILE_ROW], error: null } });
    const profiles = await listCreditProfiles(client, TENANT_ID);
    assert.equal(client.calls.table[0], "credit_profiles_directory");
    assert.equal(profiles[0]?.status, "active");
  });
});

describe("getCreditProfileForAccount", () => {
  test("returns null when the account has never had a profile", async () => {
    const client = fakeClient({ tableResponse: { data: [], error: null } });
    const profile = await getCreditProfileForAccount(client, ACCOUNT_ID);
    assert.equal(profile, null);
  });

  test("returns the most recently created profile row", async () => {
    const client = fakeClient({ tableResponse: { data: [PROFILE_ROW], error: null } });
    const profile = await getCreditProfileForAccount(client, ACCOUNT_ID);
    assert.equal(profile?.id, PROFILE_ID);
  });
});

describe("getCreditProfileById", () => {
  test("wraps a query error", async () => {
    const client = fakeClient({ tableResponse: { data: null, error: { message: "boom" } } });
    await assert.rejects(
      () => getCreditProfileById(client, PROFILE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CreditQueryError);
        return true;
      },
    );
  });
});

describe("listCreditProfileOverrides", () => {
  test("reads from the masked overrides directory view", async () => {
    const client = fakeClient({ tableResponse: { data: [], error: null } });
    await listCreditProfileOverrides(client, PROFILE_ID);
    assert.equal(client.calls.table[0], "credit_profile_overrides_directory");
  });
});

describe("getCreditProfileApprovalOverview", () => {
  test("returns null when the profile was never routed", async () => {
    const client = fakeClient({});
    const overview = await getCreditProfileApprovalOverview(client, { tenantId: TENANT_ID, approvalRequestId: null }, ACTOR_ID);
    assert.equal(overview, null);
  });

  test("composes history and eligible steps when routed", async () => {
    const client = fakeClient({ rpcResponse: { data: [], error: null } });
    const overview = await getCreditProfileApprovalOverview(client, { tenantId: TENANT_ID, approvalRequestId: REQUEST_ID }, ACTOR_ID);
    assert.ok(overview);
    assert.deepEqual(overview.history, []);
    assert.deepEqual(overview.myEligibleStepIds, []);
  });
});

describe("listCreditProfileApprovalInboxForActor", () => {
  test("returns an empty array when nothing is pending", async () => {
    const client = fakeClient({ rpcResponse: { data: [], error: null } });
    const items = await listCreditProfileApprovalInboxForActor(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(items, []);
  });
});
