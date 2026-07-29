import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  prepareFinanceVendorBillFromActualCost,
  submitFinanceVendorBillForApproval,
  discardFinanceVendorBillDraft,
  approveFinanceVendorBill,
  postFinanceVendorBill,
  VendorBillMutationError,
  type VendorBillMutationRpcClient,
} from "./vendor-bill.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTUAL_COST_ID = "323e4567-e89b-12d3-a456-426614174000";
const VENDOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const BILL_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const BILL_ROW = {
  id: BILL_ID, tenant_id: TENANT_ID, company_id: null, bill_number: null,
  vendor_master_id: VENDOR_ID, vendor_reference: null, shipment_order_id: null, actual_cost_id: ACTUAL_COST_ID,
  currency: "IDR", status: "draft", subtotal_amount: "10250000.00", tax_amount: "0.00", total_amount: "10250000.00",
  vendor_stated_amount: null, variance_amount: "0.00", variance_status: "within_tolerance",
  payment_term_days: 30, bill_date: "2026-03-15", due_date: "2026-04-14", posting_period_id: null, ap_open_item_id: null,
  submitted_by: null, submitted_at: null, approved_by: null, approved_at: null, posted_by: null, posted_at: null,
  void_reason: null, voided_by: null, voided_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): VendorBillMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorBillMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("prepareFinanceVendorBillFromActualCost", () => {
  test("calls prepare_finance_vendor_bill_from_actual_cost with the exact snake_case params", async () => {
    const client = fakeClient({ data: BILL_ROW, error: null });
    await prepareFinanceVendorBillFromActualCost(client, {
      tenantId: TENANT_ID, actualCostId: ACTUAL_COST_ID, vendorMasterId: VENDOR_ID, billDate: "2026-03-15",
      vendorStatedAmount: 10250500, taxCode: "PPN", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "prepare_finance_vendor_bill_from_actual_cost");
    assert.equal(client.calls[0]?.args.p_vendor_stated_amount, 10250500);
    assert.equal(client.calls[0]?.args.p_tax_code, "PPN");
  });

  test("wraps a finance_vendor_bill_no_matching_components error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_vendor_bill_no_matching_components: actual cost has no components sourced from vendor" } });
    await assert.rejects(
      () => prepareFinanceVendorBillFromActualCost(client, { tenantId: TENANT_ID, actualCostId: ACTUAL_COST_ID, vendorMasterId: VENDOR_ID, billDate: "2026-03-15", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof VendorBillMutationError && error.code === "finance_vendor_bill_no_matching_components",
    );
  });
});

describe("submitFinanceVendorBillForApproval / discardFinanceVendorBillDraft / approveFinanceVendorBill", () => {
  test("submitFinanceVendorBillForApproval calls submit_finance_vendor_bill_for_approval", async () => {
    const client = fakeClient({ data: { ...BILL_ROW, status: "submitted" }, error: null });
    const bill = await submitFinanceVendorBillForApproval(client, { billId: BILL_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(bill.status, "submitted");
  });

  test("discardFinanceVendorBillDraft wraps a finance_vendor_bill_not_cancellable error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_vendor_bill_not_cancellable: bill is posted, only a draft or submitted bill may be discarded" } });
    await assert.rejects(
      () => discardFinanceVendorBillDraft(client, { billId: BILL_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof VendorBillMutationError && error.code === "finance_vendor_bill_not_cancellable",
    );
  });

  test("approveFinanceVendorBill wraps a finance_vendor_bill_not_submitted error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_vendor_bill_not_submitted: bill is draft not submitted" } });
    await assert.rejects(
      () => approveFinanceVendorBill(client, { billId: BILL_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof VendorBillMutationError && error.code === "finance_vendor_bill_not_submitted",
    );
  });
});

describe("postFinanceVendorBill", () => {
  test("calls post_finance_vendor_bill and returns a bill_number", async () => {
    const client = fakeClient({ data: { ...BILL_ROW, status: "posted", bill_number: "BILL-2026-000001" }, error: null });
    const bill = await postFinanceVendorBill(client, { billId: BILL_ID, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(bill.status, "posted");
    assert.equal(bill.billNumber, "BILL-2026-000001");
  });

  test("wraps a finance_vendor_bill_period_not_open error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_vendor_bill_period_not_open: fiscal period 2026-03 is not open" } });
    await assert.rejects(
      () => postFinanceVendorBill(client, { billId: BILL_ID, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof VendorBillMutationError && error.code === "finance_vendor_bill_period_not_open",
    );
  });
});
