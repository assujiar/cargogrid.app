import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createFinanceTaxRuleDraft,
  attachFinanceTaxRuleEvidence,
  discardFinanceTaxRuleDraft,
  approveFinanceTaxRule,
  TaxBaselineMutationError,
  type TaxBaselineMutationRpcClient,
} from "./tax-baseline.ts";

const TAX_CODE_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const RULE_ROW = {
  id: RULE_ID,
  tenant_id: TENANT_ID,
  tax_code_id: TAX_CODE_ID,
  rate_basis: "percentage",
  rate_value: "0.110000",
  currency: null,
  output_account_id: null,
  recoverable_account_id: null,
  effective_from: "2026-01-01",
  effective_to: null,
  status: "draft",
  is_example_fixture: false,
  evidence_reference_file_id: null,
  evidence_note: null,
  approved_by: null,
  approved_at: null,
  archived_reason: null,
  record_version: 1,
  created_by: "finance-manager",
  created_at: "2026-01-01T00:00:00.000Z",
  updated_at: "2026-01-01T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): TaxBaselineMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TaxBaselineMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("createFinanceTaxRuleDraft", () => {
  test("calls create_finance_tax_rule_draft with the exact snake_case params", async () => {
    const client = fakeClient({ data: RULE_ROW, error: null });
    await createFinanceTaxRuleDraft(client, {
      taxCodeId: TAX_CODE_ID,
      rateBasis: "percentage",
      rateValue: 0.11,
      effectiveFrom: "2026-01-01",
      actorAuthUserId: ACTOR_ID,
      createdBy: "finance-manager",
    });
    assert.equal(client.calls[0]?.fn, "create_finance_tax_rule_draft");
    assert.equal(client.calls[0]?.args.p_tax_code_id, TAX_CODE_ID);
    assert.equal(client.calls[0]?.args.p_rate_value, 0.11);
  });

  test("wraps a finance_tax_rule_unsupported_basis error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_tax_rule_unsupported_basis: formula is not a supported rate basis" } });
    await assert.rejects(
      () => createFinanceTaxRuleDraft(client, { taxCodeId: TAX_CODE_ID, rateBasis: "percentage", rateValue: 0.11, effectiveFrom: "2026-01-01", actorAuthUserId: ACTOR_ID, createdBy: "fm" }),
      (error: unknown) => error instanceof TaxBaselineMutationError && error.code === "finance_tax_rule_unsupported_basis",
    );
  });
});

describe("attachFinanceTaxRuleEvidence", () => {
  test("calls attach_finance_tax_rule_evidence with the exact snake_case params", async () => {
    const client = fakeClient({ data: RULE_ROW, error: null });
    await attachFinanceTaxRuleEvidence(client, { ruleId: RULE_ID, expectedVersion: 1, evidenceNote: "SME memo", actorAuthUserId: ACTOR_ID, actorLabel: "finance-manager" });
    assert.equal(client.calls[0]?.fn, "attach_finance_tax_rule_evidence");
    assert.equal(client.calls[0]?.args.p_evidence_note, "SME memo");
  });
});

describe("discardFinanceTaxRuleDraft", () => {
  test("wraps a finance_tax_rule_not_draft error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_tax_rule_not_draft: rule is approved not draft" } });
    await assert.rejects(
      () => discardFinanceTaxRuleDraft(client, { ruleId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof TaxBaselineMutationError && error.code === "finance_tax_rule_not_draft",
    );
  });
});

describe("approveFinanceTaxRule", () => {
  test("calls approve_finance_tax_rule with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...RULE_ROW, status: "approved", approved_by: "finance-manager" }, error: null });
    const approved = await approveFinanceTaxRule(client, { ruleId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "finance-manager" });
    assert.equal(approved.status, "approved");
    assert.equal(client.calls[0]?.fn, "approve_finance_tax_rule");
  });

  test("wraps a finance_tax_rule_example_fixture_not_activatable error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_tax_rule_example_fixture_not_activatable: rule is a seeded illustrative example" } });
    await assert.rejects(
      () => approveFinanceTaxRule(client, { ruleId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof TaxBaselineMutationError && error.code === "finance_tax_rule_example_fixture_not_activatable",
    );
  });

  test("wraps a finance_tax_rule_overlap error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_tax_rule_overlap: an approved rule already covers an overlapping window" } });
    await assert.rejects(
      () => approveFinanceTaxRule(client, { ruleId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof TaxBaselineMutationError && error.code === "finance_tax_rule_overlap",
    );
  });
});
