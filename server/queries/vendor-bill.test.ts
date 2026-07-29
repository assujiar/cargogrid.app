import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceVendorBills, getFinanceVendorBillLines, VendorBillQueryError, type VendorBillQueryRpcClient } from "./vendor-bill.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const BILL_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): VendorBillQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorBillQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

const BILL_ROW = {
  id: BILL_ID, tenant_id: TENANT_ID, company_id: null, bill_number: null,
  vendor_master_id: TENANT_ID, vendor_reference: null, shipment_order_id: null, actual_cost_id: TENANT_ID,
  currency: "IDR", status: "draft", subtotal_amount: "10250000.00", tax_amount: "0.00", total_amount: "10250000.00",
  vendor_stated_amount: null, variance_amount: "0.00", variance_status: "within_tolerance",
  payment_term_days: 30, bill_date: "2026-03-15", due_date: "2026-04-14", posting_period_id: null, ap_open_item_id: null,
  submitted_by: null, submitted_at: null, approved_by: null, approved_at: null, posted_by: null, posted_at: null,
  void_reason: null, voided_by: null, voided_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

describe("listFinanceVendorBills", () => {
  test("maps every returned row", async () => {
    const client = fakeRpcClient({ data: [BILL_ROW], error: null });
    const bills = await listFinanceVendorBills(client, { tenantId: TENANT_ID, companyId: null, vendorMasterId: null, status: null, actorAuthUserId: ACTOR_ID });
    assert.equal(bills.length, 1);
    assert.equal(bills[0]?.status, "draft");
  });

  test("wraps a database error into a typed VendorBillQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => listFinanceVendorBills(client, { tenantId: TENANT_ID, companyId: null, vendorMasterId: null, status: null, actorAuthUserId: ACTOR_ID }),
      VendorBillQueryError,
    );
  });
});

describe("getFinanceVendorBillLines", () => {
  test("maps every returned line row", async () => {
    const client = fakeRpcClient({
      data: [{ id: BILL_ID, bill_id: BILL_ID, line_number: 1, line_type: "cost", description: "Ocean freight", amount: "10250000.00", source_component_id: TENANT_ID, tax_code_id: null, tax_rule_version_id: null, created_at: "2026-03-10T00:00:00.000Z" }],
      error: null,
    });
    const lines = await getFinanceVendorBillLines(client, { billId: BILL_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(lines.length, 1);
    assert.equal(lines[0]?.amount, 10250000);
  });
});
