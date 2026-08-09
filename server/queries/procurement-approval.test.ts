import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listProcurementApprovalPolicyVersions,
  evaluateProcurementApprovalRequirement,
  getProcurementApprovalContextSnapshot,
  listProcurementApprovalInboxForActor,
  type ProcurementApprovalQueryClient,
} from "./procurement-approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const POLICY_ID = "323e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "723e4567-e89b-12d3-a456-426614174000";
const ENTITY_ID = "823e4567-e89b-12d3-a456-426614174000";
const OTHER_REQUEST_ID = "923e4567-e89b-12d3-a456-426614174000";
const SNAPSHOT_ID = "a23e4567-e89b-12d3-a456-426614174000";

const POLICY_ROW = {
  id: POLICY_ID,
  tenant_id: TENANT_ID,
  entity_type: "vendor_activation",
  min_value_amount: null,
  always_required: true,
  status: "published",
  supersedes_version_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-07T00:00:00.000Z",
  updated_at: "2026-08-07T00:00:00.000Z",
};

function fakeClient(opts: {
  tableResponses?: Record<string, { data: unknown; error: { message: string } | null }>;
  rpcResponses?: Record<string, { data: unknown; error: { message: string } | null }>;
}): ProcurementApprovalQueryClient & { calls: { table: string[]; rpc: { fn: string; args: Record<string, unknown> }[] } } {
  const calls = { table: [] as string[], rpc: [] as { fn: string; args: Record<string, unknown> }[] };
  const fake = {
    calls,
    from(table: string) {
      calls.table.push(table);
      const response = opts.tableResponses?.[table] ?? { data: [], error: null };
      const chain = {
        eq: () => chain,
        order: () => response,
        in: () => response,
      };
      return { select: () => chain };
    },
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.rpc.push({ fn, args });
      return opts.rpcResponses?.[fn] ?? { data: [], error: null };
    },
  };
  return fake as unknown as ProcurementApprovalQueryClient & { calls: typeof calls };
}

describe("listProcurementApprovalPolicyVersions", () => {
  test("reads from procurement_approval_policies, newest first", async () => {
    const client = fakeClient({ tableResponses: { procurement_approval_policies: { data: [POLICY_ROW], error: null } } });
    const policies = await listProcurementApprovalPolicyVersions(client, TENANT_ID);
    assert.equal(client.calls.table[0], "procurement_approval_policies");
    assert.equal(policies[0]?.entityType, "vendor_activation");
  });
});

describe("evaluateProcurementApprovalRequirement", () => {
  test("passes the actor through and parses the returned row", async () => {
    const client = fakeClient({
      rpcResponses: { evaluate_procurement_approval_requirement: { data: [{ required: true, reasons: ["always_required"], policy_version_id: POLICY_ID }], error: null } },
    });
    const requirement = await evaluateProcurementApprovalRequirement(client, { entityType: "vendor_activation", tenantId: TENANT_ID, valueAmount: null, actorAuthUserId: ACTOR_ID });
    assert.equal(requirement.required, true);
    assert.equal(client.calls.rpc[0]?.args.p_actor_auth_user_id, ACTOR_ID);
  });

  // Full-regression review (Prompt 269 follow-up, this checkpoint): ISS-2026-045
  // (Fix 3) added p_value_currency to app.evaluate_procurement_approval_requirement,
  // but neither this wrapper nor its two UI call sites originally threaded a currency
  // through at all -- the client-facing preview stayed currency-blind even though
  // real submit-time enforcement was already fixed. These two cases guard the fix.
  test("threads a supplied valueCurrency through as p_value_currency", async () => {
    const client = fakeClient({
      rpcResponses: { evaluate_procurement_approval_requirement: { data: [{ required: false, reasons: [], policy_version_id: null }], error: null } },
    });
    await evaluateProcurementApprovalRequirement(client, {
      entityType: "purchase_order",
      tenantId: TENANT_ID,
      valueAmount: 20_000_000,
      actorAuthUserId: ACTOR_ID,
      valueCurrency: "IDR",
    });
    assert.equal(client.calls.rpc[0]?.args.p_value_currency, "IDR");
  });

  test("defaults p_value_currency to null when the caller omits it (legacy, same-currency-assumed shape)", async () => {
    const client = fakeClient({
      rpcResponses: { evaluate_procurement_approval_requirement: { data: [{ required: true, reasons: ["always_required"], policy_version_id: POLICY_ID }], error: null } },
    });
    await evaluateProcurementApprovalRequirement(client, { entityType: "vendor_activation", tenantId: TENANT_ID, valueAmount: null, actorAuthUserId: ACTOR_ID });
    assert.equal(client.calls.rpc[0]?.args.p_value_currency, null);
  });
});

describe("getProcurementApprovalContextSnapshot", () => {
  test("parses a masked row", async () => {
    const client = fakeClient({
      rpcResponses: {
        get_procurement_approval_context_snapshot: {
          data: [
            {
              id: SNAPSHOT_ID,
              approval_request_id: REQUEST_ID,
              tenant_id: TENANT_ID,
              entity_type: "rate_version",
              entity_id: ENTITY_ID,
              value_amount: null,
              currency: null,
              cost_masked: true,
              reasons: [],
              policy_version_id: null,
              context: {},
              source_record_version: 1,
              created_by: "tester",
              created_at: "2026-08-07T00:00:00.000Z",
            },
          ],
          error: null,
        },
      },
    });
    const snapshot = await getProcurementApprovalContextSnapshot(client, { approvalRequestId: REQUEST_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(snapshot.costMasked, true);
  });
});

describe("listProcurementApprovalInboxForActor", () => {
  test("returns an empty inbox with no follow-up round-trip when no steps are pending", async () => {
    const client = fakeClient({ rpcResponses: { list_pending_approval_steps_for_actor: { data: [], error: null } } });
    const items = await listProcurementApprovalInboxForActor(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(items, []);
    assert.equal(client.calls.table.length, 0);
  });

  test("filters out non-procurement entity requests (e.g. a Commercial quotation approval) and resolves the rest", async () => {
    const client = fakeClient({
      rpcResponses: {
        list_pending_approval_steps_for_actor: {
          data: [
            { id: STEP_ID, request_id: REQUEST_ID, step_order: 1, approver_type: "role", role_id: null, specific_user_id: ACTOR_ID, required_approvals: 1, approvals_count: 0, status: "active", created_at: "2026-08-07T00:00:00.000Z", updated_at: "2026-08-07T00:00:00.000Z" },
            { id: "b23e4567-e89b-12d3-a456-426614174000", request_id: OTHER_REQUEST_ID, step_order: 1, approver_type: "role", role_id: null, specific_user_id: ACTOR_ID, required_approvals: 1, approvals_count: 0, status: "active", created_at: "2026-08-07T00:00:00.000Z", updated_at: "2026-08-07T00:00:00.000Z" },
          ],
          error: null,
        },
      },
      tableResponses: {
        approval_requests: {
          data: [
            { id: REQUEST_ID, entity_type: "vendor_activation", entity_id: ENTITY_ID },
            { id: OTHER_REQUEST_ID, entity_type: "quotation", entity_id: "c23e4567-e89b-12d3-a456-426614174000" },
          ],
          error: null,
        },
      },
    });

    const items = await listProcurementApprovalInboxForActor(client, TENANT_ID, ACTOR_ID);
    assert.equal(items.length, 1);
    assert.equal(items[0]?.entityType, "vendor_activation");
    assert.equal(items[0]?.stepId, STEP_ID);
  });
});
