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

function fakeClient(opts: { rpcResponse?: { data: unknown; error: { message: string } | null } }): AccountQueryClient & {
  calls: { rpc: { fn: string; args: Record<string, unknown> }[] };
} {
  const calls = {
    rpc: [] as { fn: string; args: Record<string, unknown> }[],
  };
  const fake = {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.rpc.push({ fn, args });
      return opts.rpcResponse ?? { data: [], error: null };
    },
  };
  return fake as unknown as AccountQueryClient & { calls: typeof calls };
}

describe("listAccounts", () => {
  test("calls list_accounts with tenant/actor/limit, newest first", async () => {
    const client = fakeClient({ rpcResponse: { data: [ACCOUNT_ROW], error: null } });
    const accounts = await listAccounts(client, TENANT_ID, ACTOR_ID);
    assert.equal(client.calls.rpc[0]?.fn, "list_accounts");
    assert.deepEqual(client.calls.rpc[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_limit: 200 });
    assert.equal(accounts.rows[0]?.legalName, "Contoso Ltd");
    assert.equal(accounts.truncated, false);
  });

  test("reports truncated when the row count reaches the cap", async () => {
    const client = fakeClient({ rpcResponse: { data: Array.from({ length: 200 }, () => ACCOUNT_ROW), error: null } });
    const accounts = await listAccounts(client, TENANT_ID, ACTOR_ID);
    assert.equal(accounts.truncated, true);
  });
});

describe("getAccountById", () => {
  test("returns null when not found", async () => {
    const client = fakeClient({ rpcResponse: { data: [], error: null } });
    const account = await getAccountById(client, ACCOUNT_ID, ACTOR_ID);
    assert.equal(account, null);
  });

  test("wraps a query error", async () => {
    const client = fakeClient({ rpcResponse: { data: null, error: { message: "boom" } } });
    await assert.rejects(
      () => getAccountById(client, ACCOUNT_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof AccountQueryError);
        return true;
      },
    );
  });
});

describe("getAccountConversionForQuotation", () => {
  test("returns null when no conversion exists", async () => {
    const client = fakeClient({ rpcResponse: { data: [], error: null } });
    const conversion = await getAccountConversionForQuotation(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(conversion, null);
  });

  test("maps an existing conversion row", async () => {
    const client = fakeClient({ rpcResponse: { data: [{ account_id: ACCOUNT_ID, outcome: "created" }], error: null } });
    const conversion = await getAccountConversionForQuotation(client, { quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID });
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
