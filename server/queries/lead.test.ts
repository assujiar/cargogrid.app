import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { findDuplicateLeads, listLeads, getLeadById, LeadQueryError, type LeadQueryRpcClient } from "./lead.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LEAD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_LEAD_ROW = {
  id: LEAD_ID,
  tenant_id: TENANT_ID,
  source: "manual",
  external_reference: null,
  company_name: "Contoso Ltd",
  contact_name: "Jane Doe",
  email: "jane@contoso.test",
  phone: null,
  duplicate_fingerprint: "abc123",
  status: "new",
  disqualify_reason: null,
  score: 20,
  score_explanation: { version: 1, rules: [{ rule: "has_email", points: 20 }] },
  score_version: 1,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  assigned_at: null,
  assigned_by: null,
  qualified_at: null,
  disqualified_at: null,
  merged_into_id: null,
  merged_at: null,
  merged_by: null,
  converted_at: null,
  last_activity_at: "2026-07-23T00:00:00.000Z",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-23T00:00:00.000Z",
  updated_at: "2026-07-23T00:00:00.000Z",
};

describe("findDuplicateLeads", () => {
  test("calls find_duplicate_leads with the exact snake_case params and maps every returned row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: [VALID_LEAD_ROW], error: null };
      },
    } as unknown as LeadQueryRpcClient;
    const leads = await findDuplicateLeads(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, email: "jane@contoso.test" });

    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_email: "jane@contoso.test",
      p_phone: null,
      p_company_name: null,
    });
    assert.equal(leads.length, 1);
    assert.equal(leads[0]?.id, LEAD_ID);
  });

  test("wraps a tenant-membership error (never a silent empty result)", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "insufficient_authority: identity x holds no active membership" } };
      },
    } as unknown as LeadQueryRpcClient;
    await assert.rejects(
      () => findDuplicateLeads(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof LeadQueryError);
        return true;
      },
    );
  });
});

function fakeTableClient(
  response: { data: unknown; error: { message: string } | null; count?: number },
  capture: { calls: Record<string, unknown> },
): Pick<SupabaseClient, "from"> {
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

describe("listLeads", () => {
  test("bounds the query to one 50-row default page, ordered by last_activity_at descending", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_LEAD_ROW], error: null, count: 1 }, capture);

    const result = await listLeads(client, { tenantId: TENANT_ID, page: 1 });
    assert.equal(capture.calls.table, "leads");
    assert.equal(capture.calls.eqValue, TENANT_ID);
    assert.equal(capture.calls.orderColumn, "last_activity_at");
    assert.equal(capture.calls.ascending, false);
    assert.equal(capture.calls.from, 0);
    assert.equal(capture.calls.to, 49);
    assert.equal(result.leads.length, 1);
    assert.equal(result.totalCount, 1);
  });

  test("advances the page offset correctly for page 2 and clamps an oversized pageSize", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null, count: 0 }, capture);

    await listLeads(client, { tenantId: TENANT_ID, page: 2, pageSize: 500 });
    assert.equal(capture.calls.from, 100);
    assert.equal(capture.calls.to, 199);
  });
});

describe("getLeadById", () => {
  test("returns the parsed lead when found", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_LEAD_ROW], error: null }, capture);
    const lead = await getLeadById(client, LEAD_ID);
    assert.equal(lead?.id, LEAD_ID);
  });

  test("returns null (never an error) when RLS/no-match yields zero rows", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    const lead = await getLeadById(client, LEAD_ID);
    assert.equal(lead, null);
  });
});
