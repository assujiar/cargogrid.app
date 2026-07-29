import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceVendorBillStatusSchema,
  FinanceVendorBillVarianceStatusSchema,
  FinanceVendorBillLineTypeSchema,
  PrepareFinanceVendorBillFromActualCostInputSchema,
  parseFinanceVendorBill,
  parseFinanceVendorBillLine,
} from "./vendor-bill.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTUAL_COST_ID = "323e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const BILL_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("FinanceVendorBillStatusSchema / FinanceVendorBillVarianceStatusSchema / FinanceVendorBillLineTypeSchema", () => {
  test("accepts the five canonical lifecycle states", () => {
    for (const status of ["draft", "submitted", "approved", "posted", "void"]) {
      assert.doesNotThrow(() => FinanceVendorBillStatusSchema.parse(status));
    }
  });

  test("accepts only the two canonical variance states", () => {
    assert.doesNotThrow(() => FinanceVendorBillVarianceStatusSchema.parse("within_tolerance"));
    assert.doesNotThrow(() => FinanceVendorBillVarianceStatusSchema.parse("requires_approval"));
    assert.throws(() => FinanceVendorBillVarianceStatusSchema.parse("blocked"));
  });

  test("accepts only cost/tax as line types", () => {
    assert.doesNotThrow(() => FinanceVendorBillLineTypeSchema.parse("cost"));
    assert.doesNotThrow(() => FinanceVendorBillLineTypeSchema.parse("tax"));
    assert.throws(() => FinanceVendorBillLineTypeSchema.parse("discount"));
  });
});

describe("PrepareFinanceVendorBillFromActualCostInputSchema", () => {
  test("defaults paymentTermDays to 30 and vendorReference/vendorStatedAmount/taxCode to null", () => {
    const parsed = PrepareFinanceVendorBillFromActualCostInputSchema.parse({
      tenantId: TENANT_ID, actualCostId: ACTUAL_COST_ID, vendorMasterId: VENDOR_ID, billDate: "2026-03-15",
      actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(parsed.paymentTermDays, 30);
    assert.equal(parsed.vendorReference, null);
    assert.equal(parsed.vendorStatedAmount, null);
    assert.equal(parsed.taxCode, null);
  });

  test("requires a billDate", () => {
    assert.throws(() => PrepareFinanceVendorBillFromActualCostInputSchema.parse({
      tenantId: TENANT_ID, actualCostId: ACTUAL_COST_ID, vendorMasterId: VENDOR_ID,
      actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    }));
  });
});

describe("parseFinanceVendorBill", () => {
  test("maps a raw snake_case row, coercing string amounts", () => {
    const parsed = parseFinanceVendorBill({
      id: BILL_ID, tenant_id: TENANT_ID, company_id: null, bill_number: "BILL-2026-000001",
      vendor_master_id: VENDOR_ID, vendor_reference: "VBILL-REF-001", shipment_order_id: null, actual_cost_id: ACTUAL_COST_ID,
      currency: "IDR", status: "posted", subtotal_amount: "10250000.00", tax_amount: "1127500.00", total_amount: "11377500.00",
      vendor_stated_amount: null, variance_amount: "0.00", variance_status: "within_tolerance",
      payment_term_days: 30, bill_date: "2026-03-15", due_date: "2026-04-14", posting_period_id: null, ap_open_item_id: null,
      submitted_by: "fe", submitted_at: "2026-03-14T00:00:00.000Z", approved_by: "fm", approved_at: "2026-03-14T00:00:00.000Z",
      posted_by: "fm", posted_at: "2026-03-15T00:00:00.000Z", void_reason: null, voided_by: null, voided_at: null,
      record_version: 4, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-15T00:00:00.000Z",
    });
    assert.equal(parsed.totalAmount, 11377500);
    assert.equal(parsed.status, "posted");
    assert.equal(parsed.varianceStatus, "within_tolerance");
  });

  test("coerces a string vendor_stated_amount and preserves a nonzero variance_amount", () => {
    const parsed = parseFinanceVendorBill({
      id: BILL_ID, tenant_id: TENANT_ID, company_id: null, bill_number: null,
      vendor_master_id: VENDOR_ID, vendor_reference: null, shipment_order_id: null, actual_cost_id: ACTUAL_COST_ID,
      currency: "IDR", status: "draft", subtotal_amount: "5000000.00", tax_amount: "0.00", total_amount: "5000000.00",
      vendor_stated_amount: "5050000.00", variance_amount: "50000.00", variance_status: "requires_approval",
      payment_term_days: 30, bill_date: "2026-03-15", due_date: "2026-04-14", posting_period_id: null, ap_open_item_id: null,
      submitted_by: null, submitted_at: null, approved_by: null, approved_at: null,
      posted_by: null, posted_at: null, void_reason: null, voided_by: null, voided_at: null,
      record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.vendorStatedAmount, 5050000);
    assert.equal(parsed.varianceAmount, 50000);
    assert.equal(parsed.varianceStatus, "requires_approval");
  });
});

describe("parseFinanceVendorBillLine", () => {
  test("maps a raw snake_case cost line row", () => {
    const parsed = parseFinanceVendorBillLine({
      id: BILL_ID, bill_id: BILL_ID, line_number: 1, line_type: "cost",
      description: "Ocean freight", amount: "10250000.00", source_component_id: ACTUAL_COST_ID,
      tax_code_id: null, tax_rule_version_id: null, created_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 10250000);
    assert.equal(parsed.lineType, "cost");
    assert.equal(parsed.sourceComponentId, ACTUAL_COST_ID);
  });
});
