import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWarehouseBillingRateComponent,
  parseWarehouseBillingEvent,
  parseWarehouseBillingHandoff,
  parseWarehouseBillingCalculationPreview,
  CreateWarehouseBillingRateComponentInputSchema,
  CaptureWarehouseBillingEventInputSchema,
  RecalculateWarehouseBillingEventInputSchema,
  RecordWarehouseBillingReconciliationOutcomeInputSchema,
  WarehouseBillingTierSchema,
} from "./warehouse-billing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONTRACT_ID = "323e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const RATE_COMPONENT_ID = "723e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "823e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "923e4567-e89b-12d3-a456-426614174000";
const SOURCE_ID = "a23e4567-e89b-12d3-a456-426614174000";

describe("parseWarehouseBillingRateComponent", () => {
  test("maps a per_unit rate row", () => {
    const row = parseWarehouseBillingRateComponent({
      id: RATE_COMPONENT_ID,
      tenant_id: TENANT_ID,
      contract_id: CONTRACT_ID,
      warehouse_id: WAREHOUSE_ID,
      activity_type: "putaway",
      rate_basis: "per_unit",
      rate_uom_code: "PCS",
      unit_rate: "1500",
      minimum_amount: null,
      currency: "IDR",
      tier_schedule: null,
      time_basis_unit: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.rateBasis, "per_unit");
    assert.equal(row.unitRate, 1500);
    assert.equal(row.warehouseId, WAREHOUSE_ID);
  });

  test("maps a tenant-wide (null warehouse_id) flat rate row", () => {
    const row = parseWarehouseBillingRateComponent({
      id: RATE_COMPONENT_ID,
      tenant_id: TENANT_ID,
      contract_id: CONTRACT_ID,
      warehouse_id: null,
      activity_type: "storage",
      rate_basis: "flat",
      rate_uom_code: null,
      unit_rate: "50000",
      minimum_amount: null,
      currency: "IDR",
      tier_schedule: null,
      time_basis_unit: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.warehouseId, null);
    assert.equal(row.rateUomCode, null);
  });

  test("maps a tiered rate row's own tier_schedule", () => {
    const row = parseWarehouseBillingRateComponent({
      id: RATE_COMPONENT_ID,
      tenant_id: TENANT_ID,
      contract_id: CONTRACT_ID,
      warehouse_id: WAREHOUSE_ID,
      activity_type: "storage",
      rate_basis: "tiered",
      rate_uom_code: "PCS",
      unit_rate: "0",
      minimum_amount: null,
      currency: "IDR",
      tier_schedule: [
        { threshold: 100, rate: 500 },
        { threshold: 500, rate: 300 },
      ],
      time_basis_unit: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.tierSchedule?.length, 2);
    assert.equal(row.tierSchedule?.[1]?.rate, 300);
  });
});

describe("WarehouseBillingTierSchema", () => {
  test("rejects a negative rate", () => {
    assert.throws(() => WarehouseBillingTierSchema.parse({ threshold: 10, rate: -1 }));
  });
  test("rejects a non-positive threshold", () => {
    assert.throws(() => WarehouseBillingTierSchema.parse({ threshold: 0, rate: 5 }));
  });
  test("accepts a well-formed tier", () => {
    const tier = WarehouseBillingTierSchema.parse({ threshold: 10, rate: 5 });
    assert.equal(tier.threshold, 10);
  });
});

describe("parseWarehouseBillingEvent", () => {
  test("maps a draft event with every calculated field null", () => {
    const row = parseWarehouseBillingEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: ACCOUNT_ID,
      activity_type: "putaway",
      source_type: "wms_putaway_confirmation",
      source_id: SOURCE_ID,
      source_version: 1,
      activity_date: "2026-08-04T00:00:00.000Z",
      quantity: "10",
      uom_code: "PCS",
      contract_id: null,
      rate_component_id: null,
      base_amount: null,
      tax_code: null,
      tax_rule_version_id: null,
      tax_amount: null,
      total_amount: null,
      currency: null,
      rounding_mode: null,
      calculation_explanation: {},
      status: "draft",
      hold_reason: null,
      reviewed_by_auth_user_id: null,
      reviewed_by_label: null,
      reviewed_at: null,
      approved_by_auth_user_id: null,
      approved_by_label: null,
      approved_at: null,
      corrects_event_id: null,
      reverses_event_id: null,
      correction_reason: null,
      idempotency_key: "idem-1",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T00:00:00.000Z",
    });
    assert.equal(row.status, "draft");
    assert.equal(row.baseAmount, null);
    assert.equal(row.quantity, 10);
  });

  test("maps an approved event carrying a full calculation breakdown", () => {
    const row = parseWarehouseBillingEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      owner_account_id: ACCOUNT_ID,
      activity_type: "outbound",
      source_type: "wms_billing_eligibility_event",
      source_id: SOURCE_ID,
      source_version: 1,
      activity_date: "2026-08-04T00:00:00.000Z",
      quantity: "25",
      uom_code: "PCS",
      contract_id: CONTRACT_ID,
      rate_component_id: RATE_COMPONENT_ID,
      base_amount: "12500",
      tax_code: "PPN",
      tax_rule_version_id: "b23e4567-e89b-12d3-a456-426614174000",
      tax_amount: "1375",
      total_amount: "13875",
      currency: "IDR",
      rounding_mode: "round_half_up",
      calculation_explanation: { rateBasis: "per_unit" },
      status: "approved",
      hold_reason: null,
      reviewed_by_auth_user_id: ACTOR_ID,
      reviewed_by_label: "supervisor",
      reviewed_at: "2026-08-04T01:00:00.000Z",
      approved_by_auth_user_id: ACTOR_ID,
      approved_by_label: "manager",
      approved_at: "2026-08-04T02:00:00.000Z",
      corrects_event_id: null,
      reverses_event_id: null,
      correction_reason: null,
      idempotency_key: "idem-2",
      record_version: 3,
      created_by: "rep",
      created_at: "2026-08-04T00:00:00.000Z",
      updated_at: "2026-08-04T02:00:00.000Z",
    });
    assert.equal(row.totalAmount, 13875);
    assert.equal(row.baseAmount, 12500);
    assert.equal(row.taxAmount, 1375);
  });
});

describe("parseWarehouseBillingHandoff", () => {
  test("maps a pending-reconciliation handoff", () => {
    const row = parseWarehouseBillingHandoff({
      id: HANDOFF_ID,
      tenant_id: TENANT_ID,
      billing_event_id: EVENT_ID,
      idempotency_key: "idem-handoff-1",
      handed_off_by_auth_user_id: ACTOR_ID,
      handed_off_by_label: "rep",
      handed_off_at: "2026-08-04T03:00:00.000Z",
      reconciliation_status: null,
      reconciliation_note: null,
      reconciled_at: null,
      updated_at: null,
      created_at: "2026-08-04T03:00:00.000Z",
    });
    assert.equal(row.reconciliationStatus, null);
  });

  test("maps a reconciled handoff", () => {
    const row = parseWarehouseBillingHandoff({
      id: HANDOFF_ID,
      tenant_id: TENANT_ID,
      billing_event_id: EVENT_ID,
      idempotency_key: "idem-handoff-1",
      handed_off_by_auth_user_id: ACTOR_ID,
      handed_off_by_label: "rep",
      handed_off_at: "2026-08-04T03:00:00.000Z",
      reconciliation_status: "reconciled",
      reconciliation_note: "matched",
      reconciled_at: "2026-08-05T00:00:00.000Z",
      updated_at: "2026-08-05T00:00:00.000Z",
      created_at: "2026-08-04T03:00:00.000Z",
    });
    assert.equal(row.reconciliationStatus, "reconciled");
    assert.equal(row.reconciliationNote, "matched");
  });
});

describe("parseWarehouseBillingCalculationPreview", () => {
  test("maps a preview breakdown with no tax", () => {
    const preview = parseWarehouseBillingCalculationPreview({
      contractId: CONTRACT_ID,
      rateComponentId: RATE_COMPONENT_ID,
      baseAmount: 5000,
      taxCode: null,
      taxAmount: 0,
      taxRuleVersionId: null,
      totalAmount: 5000,
      currency: "IDR",
      roundingMode: "round_half_up",
      calculationExplanation: { rateBasis: "flat" },
    });
    assert.equal(preview.totalAmount, 5000);
    assert.equal(preview.taxCode, null);
  });
});

describe("CreateWarehouseBillingRateComponentInputSchema", () => {
  test("accepts a well-formed per_unit rate input", () => {
    const parsed = CreateWarehouseBillingRateComponentInputSchema.parse({
      contractId: CONTRACT_ID,
      warehouseId: WAREHOUSE_ID,
      activityType: "putaway",
      rateBasis: "per_unit",
      rateUomCode: "PCS",
      unitRate: 1500,
      currency: "IDR",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.rateBasis, "per_unit");
  });

  test("rejects a negative unit_rate", () => {
    assert.throws(() =>
      CreateWarehouseBillingRateComponentInputSchema.parse({
        contractId: CONTRACT_ID,
        activityType: "storage",
        rateBasis: "flat",
        unitRate: -1,
        currency: "IDR",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("CaptureWarehouseBillingEventInputSchema", () => {
  test("accepts a well-formed capture input", () => {
    const parsed = CaptureWarehouseBillingEventInputSchema.parse({
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      ownerAccountId: ACCOUNT_ID,
      activityType: "receiving",
      sourceType: "wms_receipt_line",
      sourceId: SOURCE_ID,
      quantity: 10,
      uomCode: "PCS",
      activityDate: "2026-08-04T00:00:00.000Z",
      idempotencyKey: "idem-capture-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.sourceType, "wms_receipt_line");
  });

  test("rejects a zero or negative quantity", () => {
    assert.throws(() =>
      CaptureWarehouseBillingEventInputSchema.parse({
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        ownerAccountId: ACCOUNT_ID,
        activityType: "receiving",
        sourceType: "wms_receipt_line",
        sourceId: SOURCE_ID,
        quantity: 0,
        uomCode: "PCS",
        activityDate: "2026-08-04T00:00:00.000Z",
        idempotencyKey: "idem-capture-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects an empty idempotency key", () => {
    assert.throws(() =>
      CaptureWarehouseBillingEventInputSchema.parse({
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        ownerAccountId: ACCOUNT_ID,
        activityType: "storage",
        sourceType: "manual",
        quantity: 1,
        uomCode: "PCS",
        activityDate: "2026-08-04T00:00:00.000Z",
        idempotencyKey: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("RecalculateWarehouseBillingEventInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      RecalculateWarehouseBillingEventInputSchema.parse({
        eventId: EVENT_ID,
        expectedVersion: 1,
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "supervisor",
      }),
    );
  });
});

describe("RecordWarehouseBillingReconciliationOutcomeInputSchema", () => {
  test("requires a non-empty note", () => {
    assert.throws(() =>
      RecordWarehouseBillingReconciliationOutcomeInputSchema.parse({
        handoffId: HANDOFF_ID,
        status: "reconciled",
        note: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "finance-worker",
      }),
    );
  });

  test("accepts a well-formed reconciliation outcome", () => {
    const parsed = RecordWarehouseBillingReconciliationOutcomeInputSchema.parse({
      handoffId: HANDOFF_ID,
      status: "rejected",
      note: "amount mismatch",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "finance-worker",
    });
    assert.equal(parsed.status, "rejected");
  });
});
