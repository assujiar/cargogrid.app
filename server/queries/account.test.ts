import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listAccounts, getAccountById, getAccountConversionForQuotation, findDuplicateAccounts, getAccountConversionReadiness, AccountQueryError, type AccountQueryClient } from "./account.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "623e4567-e89b-12d3-a456-426614174000";

const ACCOUNT_ROW = {
  id: ACCOUNT_ID,
  tenant_id: TENANT_ID,
  legal_name: "Contoso Ltd",
  trade_name: null,
  tax_id: null,
  billing_address: {},
  customer_status: "active",
  parent_account_id: null,
  source_prospect_id: null,
  status: "active",
  merged_into_id: null,
  merged_at: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeClient(opts: {
  tableResponse?: { data: unknown; error: { message: string } | null };
  rpcResponse?: { data: unknown; error: { message: string } | null };
}): AccountQueryClient & { calls: { table: string[]; rpc: { fn: string; args: Record<string, unknown> }[]; eqCalls: { column: string; value: unknown }[] } } {
  const calls = { table: [] as string[], rpc: [] as { fn: string; args: Record<string, unknown> }[], eqCalls: [] as { column: string; value: unknown }[] };
  const fake = {
    calls,
    from(table: string) {
      calls.table.push(table);
      const response = opts.tableResponse ?? { data: [], error: null };
      const chain = {
        eq(column: string, value: unknown) {
          calls.eqCalls.push({ column, value });
          return chain;
        },
        order: () => response,
        maybeSingle: async () => ({ data: Array.isArray(response.data) ? (response.data[0] ?? null) : response.data, error: response.error }),
      };
      return { select: () => chain };
    },
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.rpc.push({ fn, args });
      return opts.rpcResponse ?? { data: [], error: null };
    },
  };
  return fake as unknown as AccountQueryClient & { calls: typeof calls };
}

describe("listAccounts", () => {
  test("reads from accounts filtered by tenant_id, newest first", async () => {
    const client = fakeClient({ tableResponse: { data: [ACCOUNT_ROW], error: null } });
    const accounts = await listAccounts(client, TENANT_ID);
    assert.equal(client.calls.table[0], "accounts");
    assert.deepEqual(client.calls.eqCalls, [{ column: "tenant_id", value: TENANT_ID }]);
    assert.equal(accounts[0]?.legalName, "Contoso Ltd");
  });
});

describe("getAccountById", () => {
  test("returns null when not found", async () => {
    const client = fakeClient({ tableResponse: { data: [], error: null } });
    const account = await getAccountById(client, ACCOUNT_ID);
    assert.equal(account, null);
  });

  test("wraps a query error", async () => {
    const client = fakeClient({ tableResponse: { data: null, error: { message: "boom" } } });
    await assert.rejects(
      () => getAccountById(client, ACCOUNT_ID),
      (err: unknown) => {
        assert.ok(err instanceof AccountQueryError);
        return true;
      },
    );
  });
});

describe("getAccountConversionForQuotation", () => {
  test("returns null when no conversion exists", async () => {
    const client = fakeClient({ tableResponse: { data: [], error: null } });
    const conversion = await getAccountConversionForQuotation(client, QUOTATION_ID);
    assert.equal(conversion, null);
  });

  test("maps an existing conversion row", async () => {
    const client = fakeClient({ tableResponse: { data: [{ account_id: ACCOUNT_ID, outcome: "created" }], error: null } });
    const conversion = await getAccountConversionForQuotation(client, QUOTATION_ID);
    assert.equal(conversion?.accountId, ACCOUNT_ID);
    assert.equal(conversion?.outcome, "created");
  });
});

describe("findDuplicateAccounts", () => {
  test("calls find_duplicate_accounts with the exact snake_case params", async () => {
    const client = fakeClient({ rpcResponse: { data: [ACCOUNT_ROW], error: null } });
    const accounts = await findDuplicateAccounts(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, legalName: "Contoso Ltd" });
    assert.equal(client.calls.rpc[0]?.fn, "find_duplicate_accounts");
    assert.equal(client.calls.rpc[0]?.args.p_legal_name, "Contoso Ltd");
    assert.equal(accounts[0]?.legalName, "Contoso Ltd");
  });

  test("throws if data is not an array", async () => {
    const client = fakeClient({ rpcResponse: { data: null, error: null } });
    await assert.rejects(() => findDuplicateAccounts(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, legalName: "Contoso Ltd" }));
  });
});

describe("getAccountConversionReadiness", () => {
  test("parses a single-row RPC response", async () => {
    const client = fakeClient({ rpcResponse: { data: [{ ready: true, blocking_reasons: [], duplicate_candidate_ids: [] }], error: null } });
    const readiness = await getAccountConversionReadiness(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(readiness.ready, true);
  });

  test("wraps an RPC error", async () => {
    const client = fakeClient({ rpcResponse: { data: null, error: { message: "quotation_not_found: x" } } });
    await assert.rejects(() => getAccountConversionReadiness(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID }));
  });
});
