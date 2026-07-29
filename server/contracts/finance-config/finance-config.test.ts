import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceConfigClassSchema,
  FinanceRoundingModeSchema,
  FinanceDimensionValueSchema,
  FinanceNumberingValueSchema,
  FinancePostingMapValueSchema,
  FinanceRoundingValueSchema,
  FinanceRecognitionPolicyValueSchema,
  FinanceClosePolicyValueSchema,
  CreateFinanceConfigDraftInputSchema,
  parseResolvedFinanceConfig,
  parseFinanceConfigImpactPreview,
  parseFinanceRoundingModeInfo,
} from "./finance-config.ts";

describe("FinanceConfigClassSchema", () => {
  test("accepts the six registered Finance Configuration classes", () => {
    for (const code of [
      "finance_dimensions",
      "finance_numbering",
      "finance_posting_map",
      "finance_rounding",
      "finance_recognition",
      "finance_close_policy",
    ]) {
      assert.doesNotThrow(() => FinanceConfigClassSchema.parse(code));
    }
  });

  test("rejects an unrelated config_type_code (e.g. the platform 'approval' type)", () => {
    assert.throws(() => FinanceConfigClassSchema.parse("approval"));
  });
});

describe("FinanceRoundingModeSchema", () => {
  test("accepts the four registered rounding modes", () => {
    for (const mode of ["round_half_up", "round_half_even", "round_down", "round_up"]) {
      assert.doesNotThrow(() => FinanceRoundingModeSchema.parse(mode));
    }
  });

  test("rejects an unregistered mode", () => {
    assert.throws(() => FinanceRoundingModeSchema.parse("round_to_nearest_million"));
  });
});

describe("per-class value schemas", () => {
  test("FinanceDimensionValueSchema requires a non-empty name and boolean required flag", () => {
    assert.doesNotThrow(() => FinanceDimensionValueSchema.parse({ name: "Cost Center", required: true, valueSourceRef: null }));
    assert.throws(() => FinanceDimensionValueSchema.parse({ name: "", required: true }));
  });

  test("FinanceNumberingValueSchema requires format/resetPeriod/padding", () => {
    assert.doesNotThrow(() => FinanceNumberingValueSchema.parse({ prefix: "INV", format: "INV-{YYYY}-{SEQ}", resetPeriod: "yearly", padding: 6 }));
    assert.throws(() => FinanceNumberingValueSchema.parse({ format: "INV-{SEQ}", resetPeriod: "not_a_real_period", padding: 6 }));
    assert.throws(() => FinanceNumberingValueSchema.parse({ format: "INV-{SEQ}", resetPeriod: "yearly", padding: 0 }));
  });

  test("FinancePostingMapValueSchema requires a bounded account-code shape", () => {
    assert.doesNotThrow(() => FinancePostingMapValueSchema.parse({ accountCodeRef: "4000-AR", dimensionDefaults: {} }));
    assert.throws(() => FinancePostingMapValueSchema.parse({ accountCodeRef: "not valid!" }));
  });

  test("FinanceRoundingValueSchema requires a registered mode, bounded precision, explicit order", () => {
    assert.doesNotThrow(() => FinanceRoundingValueSchema.parse({ mode: "round_half_up", precision: 2, order: "convert_then_round" }));
    assert.throws(() => FinanceRoundingValueSchema.parse({ mode: "round_half_up", precision: 7, order: "convert_then_round" }));
    assert.throws(() => FinanceRoundingValueSchema.parse({ mode: "invented_mode", precision: 2, order: "convert_then_round" }));
  });

  test("FinanceRecognitionPolicyValueSchema requires all four bounded enums", () => {
    assert.doesNotThrow(() =>
      FinanceRecognitionPolicyValueSchema.parse({
        budgetControlMode: "advisory",
        accrualMethod: "accrual",
        revenueRecognitionMethod: "invoice_date",
        costRecognitionMethod: "incurred_date",
      }),
    );
    assert.throws(() =>
      FinanceRecognitionPolicyValueSchema.parse({
        budgetControlMode: "some_made_up_mode",
        accrualMethod: "accrual",
        revenueRecognitionMethod: "invoice_date",
        costRecognitionMethod: "incurred_date",
      }),
    );
  });

  test("FinanceClosePolicyValueSchema requires a non-empty label and boolean required flag", () => {
    assert.doesNotThrow(() => FinanceClosePolicyValueSchema.parse({ label: "AR aging reconciled", required: true, sourceCapability: "FIN-210" }));
    assert.throws(() => FinanceClosePolicyValueSchema.parse({ label: "", required: true }));
  });
});

describe("CreateFinanceConfigDraftInputSchema", () => {
  test("parses a well-formed tenant-scoped draft request", () => {
    const parsed = CreateFinanceConfigDraftInputSchema.parse({
      configTypeCode: "finance_rounding",
      tenantId: "123e4567-e89b-12d3-a456-426614174000",
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
      createdBy: "finance-admin",
    });
    assert.equal(parsed.configTypeCode, "finance_rounding");
  });

  test("rejects a configTypeCode outside the six Finance Configuration classes", () => {
    assert.throws(() =>
      CreateFinanceConfigDraftInputSchema.parse({
        configTypeCode: "approval",
        tenantId: "123e4567-e89b-12d3-a456-426614174000",
        scopeLevel: "tenant",
        scopeId: null,
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
        createdBy: "finance-admin",
      }),
    );
  });
});

describe("parseResolvedFinanceConfig", () => {
  test("maps a raw snake_case RPC row to the camelCase contract shape", () => {
    const parsed = parseResolvedFinanceConfig({
      config_type_code: "finance_rounding",
      resolved_scope_level: "tenant",
      resolved_version_id: "323e4567-e89b-12d3-a456-426614174000",
      effective_from: "2026-07-28T00:00:00Z",
      items: { default: { mode: "round_half_up", precision: 2, order: "convert_then_round" } },
    });
    assert.equal(parsed.resolvedScopeLevel, "tenant");
    assert.deepEqual(parsed.items.default, { mode: "round_half_up", precision: 2, order: "convert_then_round" });
  });
});

describe("parseFinanceConfigImpactPreview", () => {
  test("maps a raw preview-impact jsonb result, including a null pendingChartOfAccountsRefs for non-posting-map classes", () => {
    const parsed = parseFinanceConfigImpactPreview({ configTypeCode: "finance_rounding", valid: true, error: null, itemCount: 2, pendingChartOfAccountsRefs: null });
    assert.equal(parsed.valid, true);
    assert.equal(parsed.pendingChartOfAccountsRefs, null);
  });

  test("maps a posting-map preview's pendingChartOfAccountsRefs list", () => {
    const parsed = parseFinanceConfigImpactPreview({ configTypeCode: "finance_posting_map", valid: true, error: null, itemCount: 1, pendingChartOfAccountsRefs: ["4000-AR"] });
    assert.deepEqual(parsed.pendingChartOfAccountsRefs, ["4000-AR"]);
  });
});

describe("parseFinanceRoundingModeInfo", () => {
  test("maps a raw app.finance_rounding_modes row", () => {
    const parsed = parseFinanceRoundingModeInfo({ code: "round_half_up", name: "Round half up", description: "..." });
    assert.equal(parsed.code, "round_half_up");
  });
});
