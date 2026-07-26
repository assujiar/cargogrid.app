import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createQuotationApprovalRuleVersion, publishQuotationApprovalRuleVersion, decideQuotationApprovalStep, QuotationApprovalMutationError, type QuotationApprovalMutationRpcClient } from "./quotation-approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "423e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "523e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "823e4567-e89b-12d3-a456-426614174000";

const VALID_RULE_ROW = {
  id: RULE_ID,
  tenant_id: TENANT_ID,
  min_margin_pct: 40,
  max_discount_pct: null,
  min_value_amount: null,
  status: "draft",
  supersedes_version_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

const VALID_QUOTATION_ROW = {
  id: QUOTATION_ID,
  tenant_id: TENANT_ID,
  quote_number: "QTN-2026-000001",
  opportunity_id: OPPORTUNITY_ID,
  source_opportunity_version: 1,
  prospect_id: PROSPECT_ID,
  contact_id: null,
  customer_snapshot: {},
  currency: "IDR",
  validity_from: "2026-07-24T00:00:00.000Z",
  validity_to: "2026-08-24T00:00:00.000Z",
  terms: {},
  subtotal_amount: 15000000,
  discount_amount: 0,
  tax_amount: 0,
  total_amount: 15000000,
  sell_masked: false,
  status: "submitted",
  cancel_reason: null,
  cloned_from_id: null,
  document_ref: null,
  submitted_at: "2026-07-24T00:00:00.000Z",
  submitted_by: "tester",
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 2,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
  root_quotation_id: QUOTATION_ID,
  version_number: 1,
  is_current: true,
  superseded_by_id: null,
  revision_reason: null,
  approval_status: "approved",
  approval_request_id: "923e4567-e89b-12d3-a456-426614174000",
  approval_rule_version_id: RULE_ID,
  approval_required_reasons: ["below_minimum_margin"],
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): QuotationApprovalMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as QuotationApprovalMutationRpcClient;
}

describe("createQuotationApprovalRuleVersion", () => {
  test("calls create_quotation_approval_rule_version with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_RULE_ROW, error: null }, calls);
    const rule = await createQuotationApprovalRuleVersion(client, { tenantId: TENANT_ID, minMarginPct: 40, actorAuthUserId: ACTOR_ID, createdBy: "tester" });
    assert.equal(calls[0]?.fn, "create_quotation_approval_rule_version");
    assert.equal(calls[0]?.args.p_min_margin_pct, 40);
    assert.equal(calls[0]?.args.p_max_discount_pct, null);
    assert.equal(rule.status, "draft");
  });

  test("rejects at the contract layer before any rpc round-trip when every threshold is null", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_RULE_ROW, error: null }, calls);
    await assert.rejects(() => createQuotationApprovalRuleVersion(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, createdBy: "tester" }));
    assert.equal(calls.length, 0);
  });

  test("classifies insufficient_authority", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks COM:Create (missing) for tenant y" } }, []);
    await assert.rejects(
      () => createQuotationApprovalRuleVersion(client, { tenantId: TENANT_ID, minMarginPct: 40, actorAuthUserId: ACTOR_ID, createdBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationApprovalMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishQuotationApprovalRuleVersion", () => {
  test("calls publish_quotation_approval_rule_version with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RULE_ROW, status: "published" }, error: null }, calls);
    const rule = await publishQuotationApprovalRuleVersion(client, { ruleVersionId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "publish_quotation_approval_rule_version");
    assert.equal(calls[0]?.args.p_supersedes_version_id, null);
    assert.equal(rule.status, "published");
  });

  test("classifies active_rule_exists", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "active_rule_exists: tenant x already has a published quotation approval rule" } }, []);
    await assert.rejects(
      () => publishQuotationApprovalRuleVersion(client, { ruleVersionId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationApprovalMutationError);
        assert.equal(err.code, "active_rule_exists");
        return true;
      },
    );
  });
});

describe("decideQuotationApprovalStep", () => {
  test("calls decide_quotation_approval_step with the exact snake_case params and parses the returned quotation", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_QUOTATION_ROW, error: null }, calls);
    const quotation = await decideQuotationApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "finance" });
    assert.equal(calls[0]?.fn, "decide_quotation_approval_step");
    assert.equal(calls[0]?.args.p_decision, "approved");
    assert.equal(calls[0]?.args.p_reason, null);
    assert.equal(quotation.approvalStatus, "approved");
  });

  test("classifies not_a_quotation_approval", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "not_a_quotation_approval: approval request x is not a quotation approval" } }, []);
    await assert.rejects(
      () => decideQuotationApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "manager" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationApprovalMutationError);
        assert.equal(err.code, "not_a_quotation_approval");
        return true;
      },
    );
  });

  test("classifies approval_self_approval_denied", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "approval_self_approval_denied: identity x requested this approval and self-approval is not allowed" } }, []);
    await assert.rejects(
      () => decideQuotationApprovalStep(client, { requestStepId: STEP_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "requester" }),
      (err: unknown) => {
        assert.ok(err instanceof QuotationApprovalMutationError);
        assert.equal(err.code, "approval_self_approval_denied");
        return true;
      },
    );
  });
});
