import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listQuotationApprovalRuleVersions, getQuotationApprovalOverview, listQuotationApprovalInboxForActor, type QuotationApprovalQueryClient } from "./quotation-approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "723e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const OTHER_REQUEST_ID = "923e4567-e89b-12d3-a456-426614174000";

const RULE_ROW = {
  id: RULE_ID,
  tenant_id: TENANT_ID,
  min_margin_pct: 40,
  max_discount_pct: null,
  min_value_amount: null,
  status: "published",
  supersedes_version_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeClient(opts: {
  tableResponses?: Record<string, { data: unknown; error: { message: string } | null }>;
  rpcResponses?: Record<string, { data: unknown; error: { message: string } | null }>;
}): QuotationApprovalQueryClient & { calls: { table: string[]; rpc: { fn: string; args: Record<string, unknown> }[]; inCalls: unknown[] } } {
  const calls = { table: [] as string[], rpc: [] as { fn: string; args: Record<string, unknown> }[], inCalls: [] as unknown[] };
  const fake = {
    calls,
    from(table: string) {
      calls.table.push(table);
      const response = opts.tableResponses?.[table] ?? { data: [], error: null };
      const chain = {
        eq: () => chain,
        order: () => response,
        in: (_column: string, values: unknown) => {
          calls.inCalls.push(values);
          return response;
        },
      };
      return { select: () => chain };
    },
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.rpc.push({ fn, args });
      return opts.rpcResponses?.[fn] ?? { data: [], error: null };
    },
  };
  return fake as unknown as QuotationApprovalQueryClient & { calls: typeof calls };
}

describe("listQuotationApprovalRuleVersions", () => {
  test("reads from quotation_approval_rules, newest first", async () => {
    const client = fakeClient({ tableResponses: { quotation_approval_rules: { data: [RULE_ROW], error: null } } });
    const rules = await listQuotationApprovalRuleVersions(client, TENANT_ID);
    assert.equal(client.calls.table[0], "quotation_approval_rules");
    assert.equal(rules[0]?.minMarginPct, 40);
  });
});

describe("getQuotationApprovalOverview", () => {
  test("returns null when the quotation has never been routed (approvalRequestId null)", async () => {
    const client = fakeClient({});
    const overview = await getQuotationApprovalOverview(client, { tenantId: TENANT_ID, approvalRequestId: null }, ACTOR_ID);
    assert.equal(overview, null);
    assert.equal(client.calls.rpc.length, 0);
  });

  test("composes history + pending-inbox, filtering eligible steps to this quotation's own bound request", async () => {
    const client = fakeClient({
      rpcResponses: {
        get_approval_request_history: {
          data: [{ step_id: STEP_ID, step_order: 1, approver_type: "role", step_status: "active", decision_id: null, actor_auth_user_id: null, actor_label: null, decision: null, reason: null, decided_at: null }],
          error: null,
        },
        list_pending_approval_steps_for_actor: {
          data: [
            { id: STEP_ID, request_id: REQUEST_ID, step_order: 1, approver_type: "role", role_id: null, specific_user_id: ACTOR_ID, required_approvals: 1, approvals_count: 0, status: "active", created_at: "2026-07-24T00:00:00.000Z", updated_at: "2026-07-24T00:00:00.000Z" },
            { id: "a23e4567-e89b-12d3-a456-426614174000", request_id: OTHER_REQUEST_ID, step_order: 1, approver_type: "role", role_id: null, specific_user_id: ACTOR_ID, required_approvals: 1, approvals_count: 0, status: "active", created_at: "2026-07-24T00:00:00.000Z", updated_at: "2026-07-24T00:00:00.000Z" },
          ],
          error: null,
        },
      },
    });

    const overview = await getQuotationApprovalOverview(client, { tenantId: TENANT_ID, approvalRequestId: REQUEST_ID }, ACTOR_ID);
    assert.ok(overview);
    assert.equal(overview?.history.length, 1);
    assert.deepEqual(overview?.myEligibleStepIds, [STEP_ID]);
  });
});

describe("listQuotationApprovalInboxForActor", () => {
  test("returns an empty inbox with no rpc round-trip to approval_requests when no steps are pending", async () => {
    const client = fakeClient({ rpcResponses: { list_pending_approval_steps_for_actor: { data: [], error: null } } });
    const items = await listQuotationApprovalInboxForActor(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(items, []);
    assert.equal(client.calls.table.length, 0);
  });

  test("filters out non-quotation entity requests and resolves the rest to their quotationId", async () => {
    const client = fakeClient({
      rpcResponses: {
        list_pending_approval_steps_for_actor: {
          data: [
            { id: STEP_ID, request_id: REQUEST_ID, step_order: 1, approver_type: "role", role_id: null, specific_user_id: ACTOR_ID, required_approvals: 1, approvals_count: 0, status: "active", created_at: "2026-07-24T00:00:00.000Z", updated_at: "2026-07-24T00:00:00.000Z" },
            { id: "a23e4567-e89b-12d3-a456-426614174000", request_id: OTHER_REQUEST_ID, step_order: 1, approver_type: "role", role_id: null, specific_user_id: ACTOR_ID, required_approvals: 1, approvals_count: 0, status: "active", created_at: "2026-07-24T00:00:00.000Z", updated_at: "2026-07-24T00:00:00.000Z" },
          ],
          error: null,
        },
      },
      tableResponses: {
        approval_requests: {
          data: [
            { id: REQUEST_ID, entity_type: "quotation", entity_id: QUOTATION_ID },
            { id: OTHER_REQUEST_ID, entity_type: "generic", entity_id: null },
          ],
          error: null,
        },
      },
    });

    const items = await listQuotationApprovalInboxForActor(client, TENANT_ID, ACTOR_ID);
    assert.equal(items.length, 1);
    assert.equal(items[0]?.quotationId, QUOTATION_ID);
    assert.equal(items[0]?.stepId, STEP_ID);
  });
});
