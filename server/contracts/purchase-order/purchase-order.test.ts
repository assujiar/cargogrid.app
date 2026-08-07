import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parsePurchaseOrder, parsePurchaseOrderLine, parsePurchaseOrderEvent } from "./purchase-order.ts";

const PO_ID = "923e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

const VALID_PO_ROW = {
  id: PO_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  po_number: "PO-2026-000001",
  version: 1,
  revised_from_id: null,
  comparison_id: "323e4567-e89b-12d3-a456-426614174000",
  selected_offer_id: "623e4567-e89b-12d3-a456-426614174000",
  rfq_id: "423e4567-e89b-12d3-a456-426614174000",
  sourcing_request_id: "523e4567-e89b-12d3-a456-426614174000",
  vendor_master_id: "723e4567-e89b-12d3-a456-426614174000",
  currency: "IDR",
  subtotal_amount: 5000000,
  tax_code: null,
  tax_amount: 0,
  total_amount: 5000000,
  payment_term_days: 30,
  cost_masked: false,
  expected_delivery_date: null,
  service_period_start: null,
  service_period_end: null,
  commercial_terms: null,
  notes: null,
  status: "draft",
  approval_status: "not_required",
  approval_request_id: null,
  fulfillment_status: "not_started",
  fulfillment_reference: null,
  fulfillment_updated_at: null,
  fulfillment_updated_by: null,
  submitted_at: null,
  submitted_by: null,
  issued_at: null,
  issued_by: null,
  acknowledged_at: null,
  acknowledged_by: null,
  acknowledgement_note: null,
  cancelled_at: null,
  cancel_reason: null,
  idempotency_key: "idem-po-1",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-07T00:00:00.000Z",
  updated_at: "2026-08-07T00:00:00.000Z",
};

describe("parsePurchaseOrder", () => {
  test("parses a full row into camelCase", () => {
    const po = parsePurchaseOrder(VALID_PO_ROW);
    assert.equal(po.id, PO_ID);
    assert.equal(po.poNumber, "PO-2026-000001");
    assert.equal(po.subtotalAmount, 5000000);
    assert.equal(po.totalAmount, 5000000);
    assert.equal(po.status, "draft");
    assert.equal(po.approvalStatus, "not_required");
    assert.equal(po.fulfillmentStatus, "not_started");
    assert.equal(po.costMasked, false);
  });

  test("cost fields nulled and costMasked true when the caller lacks PRC:View cost", () => {
    const po = parsePurchaseOrder({ ...VALID_PO_ROW, currency: null, subtotal_amount: null, tax_amount: null, total_amount: null, payment_term_days: null, commercial_terms: null, cost_masked: true });
    assert.equal(po.currency, null);
    assert.equal(po.subtotalAmount, null);
    assert.equal(po.totalAmount, null);
    assert.equal(po.costMasked, true);
  });

  test("rejects a row missing a required field", () => {
    const { id: _id, ...rest } = VALID_PO_ROW;
    assert.throws(() => parsePurchaseOrder(rest));
  });
});

describe("parsePurchaseOrderLine", () => {
  test("parses a line row into camelCase", () => {
    const line = parsePurchaseOrderLine({
      id: "a23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      purchase_order_id: PO_ID,
      line_no: 1,
      source_requirement_line_id: "b23e4567-e89b-12d3-a456-426614174000",
      description: "General cargo",
      quantity: 100,
      uom: "kg",
      notes: null,
      created_at: "2026-08-07T00:00:00.000Z",
    });
    assert.equal(line.lineNo, 1);
    assert.equal(line.description, "General cargo");
    assert.equal(line.quantity, 100);
  });
});

describe("parsePurchaseOrderEvent", () => {
  test("parses an event row, masking reason when costMasked", () => {
    const event = parsePurchaseOrderEvent({
      id: "c23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      purchase_order_id: PO_ID,
      from_status: "draft",
      to_status: "submitted",
      reason: null,
      cost_masked: true,
      actor_auth_user_id: "823e4567-e89b-12d3-a456-426614174000",
      actor_label: "staff",
      occurred_at: "2026-08-07T00:00:00.000Z",
    });
    assert.equal(event.fromStatus, "draft");
    assert.equal(event.toStatus, "submitted");
    assert.equal(event.costMasked, true);
    assert.equal(event.reason, null);
  });
});
