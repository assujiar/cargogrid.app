import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { diffQuotationVersions } from "./quotation-diff.ts";
import type { Quotation, QuotationLine } from "./quotation.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "323e4567-e89b-12d3-a456-426614174000";

function makeQuotation(overrides: Partial<Quotation> = {}): Quotation {
  return {
    id: QUOTATION_ID,
    tenantId: TENANT_ID,
    quoteNumber: "QTN-2026-000001",
    opportunityId: "423e4567-e89b-12d3-a456-426614174000",
    sourceOpportunityVersion: 1,
    prospectId: "523e4567-e89b-12d3-a456-426614174000",
    contactId: null,
    customerSnapshot: { legalName: "Contoso Ltd" },
    currency: "IDR",
    validityFrom: "2026-07-24T00:00:00.000Z",
    validityTo: "2026-08-24T00:00:00.000Z",
    terms: {},
    subtotalAmount: 15000000,
    discountAmount: 0,
    taxAmount: 0,
    totalAmount: 15000000,
    sellMasked: false,
    status: "draft",
    cancelReason: null,
    clonedFromId: null,
    documentRef: null,
    submittedAt: null,
    submittedBy: null,
    ownerUserId: null,
    orgUnitId: null,
    recordVersion: 1,
    createdBy: "tester",
    createdAt: "2026-07-24T00:00:00.000Z",
    updatedAt: "2026-07-24T00:00:00.000Z",
    rootQuotationId: QUOTATION_ID,
    versionNumber: 1,
    isCurrent: true,
    supersededById: null,
    revisionReason: null,
    approvalStatus: "not_required",
    approvalRequestId: null,
    approvalRuleVersionId: null,
    approvalRequiredReasons: [],
    ...overrides,
  };
}

function makeLine(overrides: Partial<QuotationLine> = {}): QuotationLine {
  return {
    id: "623e4567-e89b-12d3-a456-426614174000",
    tenantId: TENANT_ID,
    quotationId: QUOTATION_ID,
    lineNo: 1,
    lineType: "service",
    description: "Ocean freight",
    marginCalculationId: null,
    quantity: 1,
    unitPrice: 15000000,
    discountPct: 0,
    taxPct: 0,
    lineGrossAmount: 15000000,
    lineDiscountAmount: 0,
    lineTaxAmount: 0,
    lineTotal: 15000000,
    costAmountSnapshot: null,
    marginPctSnapshot: null,
    sellMasked: false,
    costMasked: false,
    createdBy: "tester",
    createdAt: "2026-07-24T00:00:00.000Z",
    updatedAt: "2026-07-24T00:00:00.000Z",
    ...overrides,
  };
}

describe("diffQuotationVersions", () => {
  test("no changes -> empty diff", () => {
    const quotation = makeQuotation();
    const lines = [makeLine()];
    const diff = diffQuotationVersions({ quotation, lines }, { quotation, lines });
    assert.deepEqual(diff.headerChanges, []);
    assert.deepEqual(diff.lineChanges, []);
  });

  test("detects header field changes (currency, validity, total) but not identical fields", () => {
    const before = makeQuotation({ currency: "IDR", totalAmount: 15000000 });
    const after = makeQuotation({ currency: "USD", totalAmount: 12000000 });
    const diff = diffQuotationVersions({ quotation: before, lines: [] }, { quotation: after, lines: [] });
    const fields = diff.headerChanges.map((c) => c.field).sort();
    assert.deepEqual(fields, ["currency", "totalAmount"]);
  });

  test("detects a terms change even though it is a nested object", () => {
    const before = makeQuotation({ terms: { paymentTerms: "Net 30" } });
    const after = makeQuotation({ terms: { paymentTerms: "Net 60" } });
    const diff = diffQuotationVersions({ quotation: before, lines: [] }, { quotation: after, lines: [] });
    assert.equal(diff.headerChanges.some((c) => c.field === "terms"), true);
  });

  test("never diffs canonical identity fields that are always equal across versions of one root", () => {
    const quotation = makeQuotation();
    const diff = diffQuotationVersions({ quotation, lines: [] }, { quotation, lines: [] });
    assert.equal(diff.headerChanges.some((c) => c.field === "id" || c.field === "quoteNumber" || c.field === "rootQuotationId"), false);
  });

  test("a line present in before but not after is 'removed'", () => {
    const line = makeLine({ description: "Ocean freight" });
    const diff = diffQuotationVersions({ quotation: makeQuotation(), lines: [line] }, { quotation: makeQuotation(), lines: [] });
    assert.equal(diff.lineChanges.length, 1);
    assert.equal(diff.lineChanges[0]?.kind, "removed");
  });

  test("a line present in after but not before is 'added'", () => {
    const line = makeLine({ description: "Documentation fee", lineType: "fee" });
    const diff = diffQuotationVersions({ quotation: makeQuotation(), lines: [] }, { quotation: makeQuotation(), lines: [line] });
    assert.equal(diff.lineChanges.length, 1);
    assert.equal(diff.lineChanges[0]?.kind, "added");
  });

  test("a line correlated by marginCalculationId whose unit price changed is 'changed', not added+removed", () => {
    const calcId = "723e4567-e89b-12d3-a456-426614174000";
    const before = makeLine({ marginCalculationId: calcId, unitPrice: 15000000, lineTotal: 15000000 });
    const after = makeLine({ marginCalculationId: calcId, unitPrice: 12000000, lineTotal: 12000000 });
    const diff = diffQuotationVersions({ quotation: makeQuotation(), lines: [before] }, { quotation: makeQuotation(), lines: [after] });
    assert.equal(diff.lineChanges.length, 1);
    assert.equal(diff.lineChanges[0]?.kind, "changed");
    assert.equal(diff.lineChanges[0]?.before?.unitPrice, 15000000);
    assert.equal(diff.lineChanges[0]?.after?.unitPrice, 12000000);
  });

  test("a manual line (no margin calculation) correlated by (lineType, description) with identical numbers produces no change", () => {
    const before = makeLine({ marginCalculationId: null, lineType: "discount", description: "Loyalty discount" });
    const after = makeLine({ marginCalculationId: null, lineType: "discount", description: "Loyalty discount" });
    const diff = diffQuotationVersions({ quotation: makeQuotation(), lines: [before] }, { quotation: makeQuotation(), lines: [after] });
    assert.deepEqual(diff.lineChanges, []);
  });

  test("masked (null) fields on both sides diff as equal, never fabricating a change from missing data the caller cannot see", () => {
    const before = makeQuotation({ sellMasked: true, totalAmount: null });
    const after = makeQuotation({ sellMasked: true, totalAmount: null });
    const diff = diffQuotationVersions({ quotation: before, lines: [] }, { quotation: after, lines: [] });
    assert.equal(diff.headerChanges.some((c) => c.field === "totalAmount"), false);
  });
});
