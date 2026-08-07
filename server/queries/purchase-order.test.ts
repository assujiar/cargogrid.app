import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getPurchaseOrder, listPurchaseOrders, listPurchaseOrderLines, PurchaseOrderQueryError, type PurchaseOrderQueryRpcClient } from "./purchase-order.ts";

const PO_ID = "923e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): PurchaseOrderQueryRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PurchaseOrderQueryRpcClient;
}

describe("getPurchaseOrder", () => {
  test("calls get_purchase_order with p_purchase_order_id/p_actor_auth_user_id and unwraps the RETURNS TABLE array", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_PO_ROW], error: null }, calls);

    const po = await getPurchaseOrder(client, PO_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "get_purchase_order");
    assert.equal(calls[0]?.args.p_purchase_order_id, PO_ID);
    assert.equal(calls[0]?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(po.id, PO_ID);
  });

  test("throws PurchaseOrderQueryError on a purchase_order_not_found error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "purchase_order_not_found: 923e4567-e89b-12d3-a456-426614174000" } }, []);
    await assert.rejects(
      () => getPurchaseOrder(client, PO_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof PurchaseOrderQueryError);
        return true;
      },
    );
  });

  test("throws PurchaseOrderQueryError when the RPC returns no row and no error", async () => {
    const client = fakeRpcClient({ data: [], error: null }, []);
    await assert.rejects(() => getPurchaseOrder(client, PO_ID, ACTOR_ID));
  });
});

describe("listPurchaseOrders", () => {
  test("passes tenantId/statusFilter/vendorMasterId/limit through as p_ params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_PO_ROW], error: null }, calls);

    const rows = await listPurchaseOrders(client, TENANT_ID, ACTOR_ID, "draft", "723e4567-e89b-12d3-a456-426614174000", 25);

    assert.equal(calls[0]?.fn, "list_purchase_orders");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(calls[0]?.args.p_status_filter, "draft");
    assert.equal(calls[0]?.args.p_vendor_master_id, "723e4567-e89b-12d3-a456-426614174000");
    assert.equal(calls[0]?.args.p_limit, 25);
    assert.equal(rows.length, 1);
  });

  test("returns an empty array when data is null", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    const rows = await listPurchaseOrders(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("listPurchaseOrderLines", () => {
  test("calls list_purchase_order_lines with p_purchase_order_id/p_actor_auth_user_id", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [], error: null }, calls);

    await listPurchaseOrderLines(client, PO_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "list_purchase_order_lines");
    assert.equal(calls[0]?.args.p_purchase_order_id, PO_ID);
  });
});
