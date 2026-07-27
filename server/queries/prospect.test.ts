import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  findDuplicateProspects,
  findExistingAccountsForProspect,
  getProspectConversionReadiness,
  listProspects,
  getProspectById,
  ProspectQueryError,
  type ProspectQueryRpcClient,
} from "./prospect.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "323e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_PROSPECT_ROW = {
  id: PROSPECT_ID,
  tenant_id: TENANT_ID,
  lead_id: LEAD_ID,
  legal_name: "Contoso Ltd",
  trade_name: null,
  tax_id: null,
  billing_address: {},
  contact_name: "Jane Doe",
  contact_email: "jane@contoso.test",
  contact_phone: null,
  status: "active",
  disqualify_reason: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  merged_into_id: null,
  merged_at: null,
  merged_by: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

describe("findDuplicateProspects", () => {
  test("calls find_duplicate_prospects with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: [VALID_PROSPECT_ROW], error: null };
      },
    } as unknown as ProspectQueryRpcClient;
    const prospects = await findDuplicateProspects(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, legalName: "Contoso Ltd" });

    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_legal_name: "Contoso Ltd",
      p_tax_id: null,
    });
    assert.equal(prospects.length, 1);
  });

  test("wraps a query error", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "insufficient_authority: identity x holds no active membership" } };
      },
    } as unknown as ProspectQueryRpcClient;
    await assert.rejects(
      () => findDuplicateProspects(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ProspectQueryError);
        return true;
      },
    );
  });
});

describe("findExistingAccountsForProspect", () => {
  const ACCOUNT_ROW = {
    id: "623e4567-e89b-12d3-a456-426614174000",
    tenant_id: TENANT_ID,
    legal_name: "Contoso Ltd",
    trade_name: "Contoso",
    tax_id: "01.234.567.8-901.000",
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
    created_at: "2026-07-25T00:00:00.000Z",
    updated_at: "2026-07-25T00:00:00.000Z",
  };

  test("calls find_existing_accounts_for_prospect with the exact snake_case params and maps every returned row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: [ACCOUNT_ROW], error: null };
      },
    } as unknown as ProspectQueryRpcClient;
    const accounts = await findExistingAccountsForProspect(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, prospectId: PROSPECT_ID });

    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_prospect_id: PROSPECT_ID,
    });
    assert.equal(accounts.length, 1);
    assert.equal(accounts[0]?.legalName, "Contoso Ltd");
  });

  test("returns an empty array when no candidate account matches (never blocks qualification)", async () => {
    const client = {
      async rpc() {
        return { data: [], error: null };
      },
    } as unknown as ProspectQueryRpcClient;
    const accounts = await findExistingAccountsForProspect(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, prospectId: PROSPECT_ID });
    assert.deepEqual(accounts, []);
  });

  test("wraps a tenant-membership error (never a silent empty result)", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "insufficient_authority: identity x holds no active membership" } };
      },
    } as unknown as ProspectQueryRpcClient;
    await assert.rejects(
      () => findExistingAccountsForProspect(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, prospectId: PROSPECT_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ProspectQueryError);
        return true;
      },
    );
  });
});

describe("getProspectConversionReadiness", () => {
  test("parses a not-ready result with a missing-field list", async () => {
    const client = {
      async rpc() {
        return { data: { ready: false, missing: ["tax_id", "billing_address"] }, error: null };
      },
    } as unknown as ProspectQueryRpcClient;
    const readiness = await getProspectConversionReadiness(client, PROSPECT_ID);
    assert.equal(readiness.ready, false);
    assert.deepEqual(readiness.missing, ["tax_id", "billing_address"]);
  });

  test("parses a ready result with an empty missing list", async () => {
    const client = {
      async rpc() {
        return { data: { ready: true, missing: [] }, error: null };
      },
    } as unknown as ProspectQueryRpcClient;
    const readiness = await getProspectConversionReadiness(client, PROSPECT_ID);
    assert.equal(readiness.ready, true);
  });
});

function fakeTableClient(response: { data: unknown; error: { message: string } | null; count?: number }, capture: { calls: Record<string, unknown> }): Pick<SupabaseClient, "from"> {
  const fake = {
    from(table: string) {
      capture.calls.table = table;
      return {
        select(columns: string, options?: { count?: string }) {
          capture.calls.columns = columns;
          capture.calls.countOption = options?.count;
          return {
            eq(column: string, value: unknown) {
              capture.calls.eqColumn = column;
              capture.calls.eqValue = value;
              return {
                order(column2: string, opts: { ascending: boolean }) {
                  capture.calls.orderColumn = column2;
                  capture.calls.ascending = opts.ascending;
                  return {
                    async range(from: number, to: number) {
                      capture.calls.from = from;
                      capture.calls.to = to;
                      return response;
                    },
                  };
                },
                async maybeSingle() {
                  const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
                  return { data: row, error: response.error };
                },
              };
            },
          };
        },
      };
    },
  };
  return fake as unknown as Pick<SupabaseClient, "from">;
}

describe("listProspects", () => {
  test("bounds the query to one 50-row default page, ordered by updated_at descending", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_PROSPECT_ROW], error: null, count: 1 }, capture);

    const result = await listProspects(client, { tenantId: TENANT_ID, page: 1 });
    assert.equal(capture.calls.table, "prospects");
    assert.equal(capture.calls.orderColumn, "updated_at");
    assert.equal(capture.calls.ascending, false);
    assert.equal(capture.calls.from, 0);
    assert.equal(capture.calls.to, 49);
    assert.equal(result.prospects.length, 1);
    assert.equal(result.totalCount, 1);
  });
});

describe("getProspectById", () => {
  test("returns the parsed prospect when found", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_PROSPECT_ROW], error: null }, capture);
    const prospect = await getProspectById(client, PROSPECT_ID);
    assert.equal(prospect?.id, PROSPECT_ID);
  });

  test("returns null (never an error) when RLS/no-match yields zero rows", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    const prospect = await getProspectById(client, PROSPECT_ID);
    assert.equal(prospect, null);
  });
});
