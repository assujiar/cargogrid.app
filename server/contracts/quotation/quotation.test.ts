import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  CreateQuotationDraftInputSchema,
  AddQuotationLineInputSchema,
  UpdateQuotationTermsInputSchema,
  parseQuotation,
  parseQuotationLine,
  parseQuotationReadiness,
  toTermsJson,
} from "./quotation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "323e4567-e89b-12d3-a456-426614174000";
const OPPORTUNITY_ID = "423e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "723e4567-e89b-12d3-a456-426614174000";

const QUOTATION_ROW = {
  id: QUOTATION_ID,
  tenant_id: TENANT_ID,
  quote_number: "QTN-2026-000001",
  opportunity_id: OPPORTUNITY_ID,
  source_opportunity_version: 1,
  prospect_id: PROSPECT_ID,
  contact_id: null,
  customer_snapshot: { legal_name: "Contoso Ltd", billing_address: { city: "Jakarta" } },
  currency: "IDR",
  validity_from: "2026-07-24T00:00:00.000Z",
  validity_to: "2026-08-24T00:00:00.000Z",
  terms: { payment_terms: "Net 30" },
  subtotal_amount: 15000000,
  discount_amount: 0,
  tax_amount: 0,
  total_amount: 15000000,
  sell_masked: false,
  status: "draft",
  cancel_reason: null,
  cloned_from_id: null,
  document_ref: null,
  submitted_at: null,
  submitted_by: null,
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
  root_quotation_id: QUOTATION_ID,
  version_number: 1,
  is_current: true,
  superseded_by_id: null,
  revision_reason: null,
};

describe("parseQuotation", () => {
  test("maps a full row, including the nested customer snapshot and terms", () => {
    const quotation = parseQuotation(QUOTATION_ROW);
    assert.equal(quotation.quoteNumber, "QTN-2026-000001");
    assert.equal(quotation.customerSnapshot.legalName, "Contoso Ltd");
    assert.deepEqual(quotation.customerSnapshot.billingAddress, { city: "Jakarta" });
    assert.equal(quotation.terms.paymentTerms, "Net 30");
    assert.equal(quotation.totalAmount, 15000000);
  });

  test("nulls a masked total through unaffected (masking already applied by the directory view)", () => {
    const quotation = parseQuotation({ ...QUOTATION_ROW, sell_masked: true, subtotal_amount: null, discount_amount: null, tax_amount: null, total_amount: null });
    assert.equal(quotation.sellMasked, true);
    assert.equal(quotation.totalAmount, null);
  });
});

describe("parseQuotationLine", () => {
  test("maps a sourced line with both masking dimensions unmasked", () => {
    const line = parseQuotationLine({
      id: LINE_ID,
      tenant_id: TENANT_ID,
      quotation_id: QUOTATION_ID,
      line_no: 1,
      line_type: "service",
      description: "Ocean freight",
      margin_calculation_id: "823e4567-e89b-12d3-a456-426614174000",
      quantity: 1,
      unit_price: 15000000,
      discount_pct: 0,
      tax_pct: 0,
      line_gross_amount: 15000000,
      line_discount_amount: 0,
      line_tax_amount: 0,
      line_total: 15000000,
      cost_amount_snapshot: 10000000,
      margin_pct_snapshot: 33.33,
      sell_masked: false,
      cost_masked: false,
      created_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
      updated_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(line.lineType, "service");
    assert.equal(line.costAmountSnapshot, 10000000);
    assert.equal(line.marginPctSnapshot, 33.33);
  });

  test("a manually added line (no margin_calculation_id) carries a null cost snapshot", () => {
    const line = parseQuotationLine({
      id: LINE_ID,
      tenant_id: TENANT_ID,
      quotation_id: QUOTATION_ID,
      line_no: 2,
      line_type: "discount",
      description: "Loyalty discount",
      margin_calculation_id: null,
      quantity: 1,
      unit_price: 50000,
      discount_pct: 0,
      tax_pct: 0,
      line_gross_amount: 50000,
      line_discount_amount: 0,
      line_tax_amount: 0,
      line_total: 50000,
      cost_amount_snapshot: null,
      margin_pct_snapshot: null,
      sell_masked: false,
      cost_masked: false,
      created_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
      updated_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(line.marginCalculationId, null);
    assert.equal(line.costAmountSnapshot, null);
  });
});

describe("parseQuotationReadiness", () => {
  test("maps ready=false with blocking reasons", () => {
    const readiness = parseQuotationReadiness({ ready: false, blocking_reasons: ["no_lines", "contact_required"] });
    assert.equal(readiness.ready, false);
    assert.deepEqual(readiness.blockingReasons, ["no_lines", "contact_required"]);
  });

  test("maps ready=true with an empty reason list", () => {
    const readiness = parseQuotationReadiness({ ready: true, blocking_reasons: [] });
    assert.equal(readiness.ready, true);
    assert.deepEqual(readiness.blockingReasons, []);
  });
});

describe("CreateQuotationDraftInputSchema", () => {
  test("accepts a valid 3-letter currency", () => {
    const parsed = CreateQuotationDraftInputSchema.parse({
      tenantId: TENANT_ID,
      opportunityId: OPPORTUNITY_ID,
      currency: "IDR",
      validityTo: "2026-08-24T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(parsed.currency, "IDR");
    assert.equal(parsed.contactId, null);
  });

  test("rejects a lowercase currency code", () => {
    assert.throws(() =>
      CreateQuotationDraftInputSchema.parse({
        tenantId: TENANT_ID,
        opportunityId: OPPORTUNITY_ID,
        currency: "idr",
        validityTo: "2026-08-24T00:00:00.000Z",
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });
});

describe("AddQuotationLineInputSchema", () => {
  test("defaults discountPct/taxPct to 0", () => {
    const parsed = AddQuotationLineInputSchema.parse({
      quotationId: QUOTATION_ID,
      expectedVersion: 1,
      lineType: "service",
      description: "Ocean freight",
      quantity: 1,
      unitPrice: 15000000,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.discountPct, 0);
    assert.equal(parsed.taxPct, 0);
    assert.equal(parsed.marginCalculationId, null);
  });

  test("rejects an empty description", () => {
    assert.throws(() =>
      AddQuotationLineInputSchema.parse({
        quotationId: QUOTATION_ID,
        expectedVersion: 1,
        lineType: "service",
        description: "",
        quantity: 1,
        unitPrice: 100,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("rejects a discountPct above 100", () => {
    assert.throws(() =>
      AddQuotationLineInputSchema.parse({
        quotationId: QUOTATION_ID,
        expectedVersion: 1,
        lineType: "service",
        description: "Ocean freight",
        quantity: 1,
        unitPrice: 100,
        discountPct: 150,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("UpdateQuotationTermsInputSchema / toTermsJson", () => {
  test("round-trips whitelisted terms keys only", () => {
    const parsed = UpdateQuotationTermsInputSchema.parse({
      quotationId: QUOTATION_ID,
      expectedVersion: 1,
      currency: "IDR",
      validityFrom: "2026-07-24T00:00:00.000Z",
      validityTo: "2026-08-24T00:00:00.000Z",
      terms: { paymentTerms: "Net 30", incoterm: "FOB" },
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.deepEqual(toTermsJson(parsed.terms), { payment_terms: "Net 30", incoterm: "FOB" });
  });

  test("toTermsJson omits absent keys entirely rather than emitting null", () => {
    assert.deepEqual(toTermsJson({ paymentTerms: "Net 30" }), { payment_terms: "Net 30" });
    assert.deepEqual(toTermsJson(null), {});
  });
});
