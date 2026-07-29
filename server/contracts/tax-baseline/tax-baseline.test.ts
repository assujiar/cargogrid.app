import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceTaxCodeSchema,
  FinanceTaxRuleStatusSchema,
  FinanceTaxRateBasisSchema,
  CreateFinanceTaxRuleDraftInputSchema,
  AttachFinanceTaxRuleEvidenceInputSchema,
  DiscardFinanceTaxRuleDraftInputSchema,
  ApproveFinanceTaxRuleInputSchema,
  CalculateFinanceTaxInputSchema,
  parseFinanceTaxCode,
  parseFinanceTaxRuleVersion,
  parseFinanceTaxCalculation,
} from "./tax-baseline.ts";

const TAX_CODE_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("FinanceTaxCodeSchema", () => {
  test("accepts a well-formed tax code row", () => {
    assert.doesNotThrow(() =>
      FinanceTaxCodeSchema.parse({
        id: TAX_CODE_ID,
        tenantId: null,
        code: "PPN",
        name: "Pajak Pertambahan Nilai (Value Added Tax)",
        taxType: "vat",
        jurisdictionCountry: "ID",
        isRecoverable: true,
        isActive: true,
      }),
    );
  });

  test("rejects an unrecognized tax type", () => {
    assert.throws(() =>
      FinanceTaxCodeSchema.parse({
        id: TAX_CODE_ID,
        tenantId: null,
        code: "PPN",
        name: "x",
        taxType: "invented_rate",
        jurisdictionCountry: "ID",
        isRecoverable: true,
        isActive: true,
      }),
    );
  });
});

describe("FinanceTaxRuleStatusSchema / FinanceTaxRateBasisSchema", () => {
  test("accepts the three canonical lifecycle states", () => {
    for (const status of ["draft", "approved", "archived"]) {
      assert.doesNotThrow(() => FinanceTaxRuleStatusSchema.parse(status));
    }
  });

  test("accepts only the two supported rate bases (no formula basis exists)", () => {
    assert.doesNotThrow(() => FinanceTaxRateBasisSchema.parse("percentage"));
    assert.doesNotThrow(() => FinanceTaxRateBasisSchema.parse("fixed_amount"));
    assert.throws(() => FinanceTaxRateBasisSchema.parse("formula"));
  });
});

describe("CreateFinanceTaxRuleDraftInputSchema", () => {
  test("parses a well-formed draft request and defaults tenantId/currency/accounts to null", () => {
    const parsed = CreateFinanceTaxRuleDraftInputSchema.parse({
      taxCodeId: TAX_CODE_ID,
      rateBasis: "percentage",
      rateValue: 0.11,
      effectiveFrom: "2026-01-01",
      actorAuthUserId: ACTOR_ID,
      createdBy: "finance-manager",
    });
    assert.equal(parsed.tenantId, null);
    assert.equal(parsed.currency, null);
    assert.equal(parsed.outputAccountId, null);
  });

  test("rejects a negative rate value", () => {
    assert.throws(() =>
      CreateFinanceTaxRuleDraftInputSchema.parse({
        taxCodeId: TAX_CODE_ID,
        rateBasis: "percentage",
        rateValue: -0.1,
        effectiveFrom: "2026-01-01",
        actorAuthUserId: ACTOR_ID,
        createdBy: "finance-manager",
      }),
    );
  });
});

describe("AttachFinanceTaxRuleEvidenceInputSchema / DiscardFinanceTaxRuleDraftInputSchema / ApproveFinanceTaxRuleInputSchema", () => {
  test("each requires ruleId, expectedVersion, and actor identity", () => {
    assert.doesNotThrow(() =>
      AttachFinanceTaxRuleEvidenceInputSchema.parse({ ruleId: RULE_ID, expectedVersion: 1, evidenceNote: "SME memo", actorAuthUserId: ACTOR_ID, actorLabel: "sme" }),
    );
    assert.doesNotThrow(() => DiscardFinanceTaxRuleDraftInputSchema.parse({ ruleId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "sme" }));
    assert.doesNotThrow(() => ApproveFinanceTaxRuleInputSchema.parse({ ruleId: RULE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "sme" }));
  });
});

describe("CalculateFinanceTaxInputSchema", () => {
  test("rejects a negative base amount", () => {
    assert.throws(() => CalculateFinanceTaxInputSchema.parse({ tenantId: TENANT_ID, taxCode: "PPN", baseAmount: -1, actorAuthUserId: ACTOR_ID }));
  });
});

describe("parseFinanceTaxCode", () => {
  test("maps a raw snake_case row", () => {
    const parsed = parseFinanceTaxCode({
      id: TAX_CODE_ID,
      tenant_id: null,
      code: "PPN",
      name: "Pajak Pertambahan Nilai (Value Added Tax)",
      tax_type: "vat",
      jurisdiction_country: "ID",
      is_recoverable: true,
      is_active: true,
    });
    assert.equal(parsed.code, "PPN");
    assert.equal(parsed.taxType, "vat");
  });
});

describe("parseFinanceTaxRuleVersion", () => {
  test("maps a raw snake_case row, coercing a string rate_value", () => {
    const parsed = parseFinanceTaxRuleVersion({
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
      status: "approved",
      is_example_fixture: false,
      evidence_reference_file_id: null,
      evidence_note: "SME memo",
      approved_by: "finance-manager",
      approved_at: "2026-01-01T00:00:00.000Z",
      archived_reason: null,
      record_version: 2,
      created_by: "finance-manager",
      created_at: "2026-01-01T00:00:00.000Z",
      updated_at: "2026-01-01T00:00:00.000Z",
    });
    assert.equal(parsed.rateValue, 0.11);
    assert.equal(parsed.status, "approved");
  });
});

describe("parseFinanceTaxCalculation", () => {
  test("maps a raw calculate_finance_tax() jsonb result, coercing string numbers", () => {
    const parsed = parseFinanceTaxCalculation({
      baseAmount: 1000000,
      taxCode: "PPN",
      ruleVersionId: RULE_ID,
      rateBasis: "percentage",
      rateValue: "0.110000",
      currency: null,
      taxAmount: "110000.00",
      roundingMode: "round_half_up",
      effectiveFrom: "2026-01-01",
      effectiveTo: null,
    });
    assert.equal(parsed.rateValue, 0.11);
    assert.equal(parsed.taxAmount, 110000);
  });
});
