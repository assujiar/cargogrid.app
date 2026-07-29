import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceTaxCodes, listFinanceTaxRuleVersions, calculateFinanceTax, TaxBaselineQueryError, type TaxBaselineQueryRpcClient } from "./tax-baseline.ts";

const TAX_CODE_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): TaxBaselineQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TaxBaselineQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("listFinanceTaxCodes", () => {
  test("maps every returned row", async () => {
    const client = fakeRpcClient({
      data: [{ id: TAX_CODE_ID, tenant_id: null, code: "PPN", name: "Value Added Tax", tax_type: "vat", jurisdiction_country: "ID", is_recoverable: true, is_active: true }],
      error: null,
    });
    const codes = await listFinanceTaxCodes(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(codes.length, 1);
    assert.equal(codes[0]?.code, "PPN");
  });

  test("wraps a database error into a typed TaxBaselineQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(() => listFinanceTaxCodes(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }), TaxBaselineQueryError);
  });
});

describe("listFinanceTaxRuleVersions", () => {
  test("maps every returned row, coercing a string rate_value", async () => {
    const client = fakeRpcClient({
      data: [
        {
          id: RULE_ID, tenant_id: TENANT_ID, tax_code_id: TAX_CODE_ID, rate_basis: "percentage", rate_value: "0.110000",
          currency: null, output_account_id: null, recoverable_account_id: null, effective_from: "2026-01-01", effective_to: null,
          status: "approved", is_example_fixture: false, evidence_reference_file_id: null, evidence_note: "memo",
          approved_by: "fm", approved_at: "2026-01-01T00:00:00.000Z", archived_reason: null, record_version: 2,
          created_by: "fm", created_at: "2026-01-01T00:00:00.000Z", updated_at: "2026-01-01T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rules = await listFinanceTaxRuleVersions(client, { tenantId: TENANT_ID, taxCodeId: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rules.length, 1);
    assert.equal(rules[0]?.rateValue, 0.11);
  });
});

describe("calculateFinanceTax", () => {
  test("parses a calculation result, coercing string numbers", async () => {
    const client = fakeRpcClient({
      data: { baseAmount: 1000000, taxCode: "PPN", ruleVersionId: RULE_ID, rateBasis: "percentage", rateValue: "0.110000", currency: null, taxAmount: "110000.00", roundingMode: "round_half_up", effectiveFrom: "2026-01-01", effectiveTo: null },
      error: null,
    });
    const result = await calculateFinanceTax(client, { tenantId: TENANT_ID, taxCode: "PPN", baseAmount: 1000000, asOf: null, actorAuthUserId: ACTOR_ID });
    assert.equal(result.taxAmount, 110000);
  });

  test("wraps a finance_tax_rule_missing error -- never a silent zero", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "finance_tax_rule_missing: no approved tax rule for PPH23 covers 2026-03-01" } });
    await assert.rejects(
      () => calculateFinanceTax(client, { tenantId: TENANT_ID, taxCode: "PPH23", baseAmount: 500000, asOf: null, actorAuthUserId: ACTOR_ID }),
      TaxBaselineQueryError,
    );
  });
});
