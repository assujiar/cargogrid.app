import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { findDuplicateLeads, findExistingAccountsForLead, listLeads, getLeadById, LeadQueryError, type LeadQueryRpcClient } from "./lead.ts";

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
  converted_prospect_id: null,
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

describe("findExistingAccountsForLead", () => {
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

  test("calls find_existing_accounts_for_lead with the exact snake_case params and maps every returned row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        return { data: [ACCOUNT_ROW], error: null };
      },
    } as unknown as LeadQueryRpcClient;
    const accounts = await findExistingAccountsForLead(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, leadId: LEAD_ID });

    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_lead_id: LEAD_ID,
    });
    assert.equal(accounts.length, 1);
    assert.equal(accounts[0]?.legalName, "Contoso Ltd");
  });

  test("returns an empty array when no candidate account matches (never blocks capture)", async () => {
    const client = {
      async rpc() {
        return { data: [], error: null };
      },
    } as unknown as LeadQueryRpcClient;
    const accounts = await findExistingAccountsForLead(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, leadId: LEAD_ID });
    assert.deepEqual(accounts, []);
  });

  test("wraps a tenant-membership error (never a silent empty result)", async () => {
    const client = {
      async rpc() {
        return { data: null, error: { message: "insufficient_authority: identity x holds no active membership" } };
      },
    } as unknown as LeadQueryRpcClient;
    await assert.rejects(
      () => findExistingAccountsForLead(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, leadId: LEAD_ID }),
      (err: unknown) => {
        assert.ok(err instanceof LeadQueryError);
        return true;
      },
    );
  });
});

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): LeadQueryRpcClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.fn = fn;
      capture.calls.args = args;
      return response;
    },
  };
  return fake as unknown as LeadQueryRpcClient;
}

describe("listLeads", () => {
  test("calls list_leads with tenant/actor/page/pageSize and maps total_count", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [{ ...VALID_LEAD_ROW, total_count: 1 }], error: null }, capture);

    const result = await listLeads(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 1 });
    assert.equal(capture.calls.fn, "list_leads");
    assert.deepEqual(capture.calls.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_page: 1, p_page_size: 50 });
    assert.equal(result.leads.length, 1);
    assert.equal(result.totalCount, 1);
  });

  test("clamps an oversized pageSize before sending it", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [], error: null }, capture);

    const result = await listLeads(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, page: 2, pageSize: 500 });
    assert.deepEqual(capture.calls.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_page: 2, p_page_size: 100 });
    assert.equal(result.totalCount, 0);
  });
});

describe("getLeadById", () => {
  test("returns the parsed lead when found", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [VALID_LEAD_ROW], error: null }, capture);
    const lead = await getLeadById(client, LEAD_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "get_lead_by_id");
    assert.deepEqual(capture.calls.args, { p_lead_id: LEAD_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(lead?.id, LEAD_ID);
  });

  test("returns null (never an error) when denied/no-match yields zero rows", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [], error: null }, capture);
    const lead = await getLeadById(client, LEAD_ID, ACTOR_ID);
    assert.equal(lead, null);
  });
});
