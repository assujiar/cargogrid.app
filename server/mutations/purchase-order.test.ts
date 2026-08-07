import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  draftPurchaseOrderFromSelection,
  submitPurchaseOrderForApproval,
  issuePurchaseOrder,
  amendPurchaseOrder,
  cancelPurchaseOrder,
  PurchaseOrderMutationError,
  type PurchaseOrderMutationRpcClient,
} from "./purchase-order.ts";

const PO_ID = "923e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const COMPARISON_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

const VALID_PO_ROW = {
  id: PO_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  po_number: "PO-2026-000001",
  version: 1,
  revised_from_id: null,
  comparison_id: COMPARISON_ID,
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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): PurchaseOrderMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PurchaseOrderMutationRpcClient;
}

describe("draftPurchaseOrderFromSelection", () => {
  test("maps camelCase input to p_ RPC params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_PO_ROW, error: null }, calls);

    const po = await draftPurchaseOrderFromSelection(client, {
      tenantId: TENANT_ID,
      comparisonId: COMPARISON_ID,
      idempotencyKey: "idem-draft-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "staff",
    });

    assert.equal(calls[0]?.fn, "draft_purchase_order_from_selection");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(calls[0]?.args.p_comparison_id, COMPARISON_ID);
    assert.equal(calls[0]?.args.p_tax_code, null);
    assert.equal(po.id, PO_ID);
  });

  test("classifies a known error prefix (selection_approval_pending) into its code", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "selection_approval_pending: vendor comparison 323e... approval_status is pending" } }, []);
    await assert.rejects(
      () =>
        draftPurchaseOrderFromSelection(client, {
          tenantId: TENANT_ID,
          comparisonId: COMPARISON_ID,
          idempotencyKey: "idem-draft-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => {
        assert.ok(err instanceof PurchaseOrderMutationError);
        assert.equal((err as PurchaseOrderMutationError).code, "selection_approval_pending");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "totally_unexpected_error: something broke" } }, []);
    await assert.rejects(
      () =>
        draftPurchaseOrderFromSelection(client, {
          tenantId: TENANT_ID,
          comparisonId: COMPARISON_ID,
          idempotencyKey: "idem-draft-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => {
        assert.ok(err instanceof PurchaseOrderMutationError);
        assert.equal((err as PurchaseOrderMutationError).code, "mutation_failed");
        return true;
      },
    );
  });

  test("throws invalid_response when the RPC returns no row and no error", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    await assert.rejects(
      () =>
        draftPurchaseOrderFromSelection(client, {
          tenantId: TENANT_ID,
          comparisonId: COMPARISON_ID,
          idempotencyKey: "idem-draft-4",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "staff",
        }),
      (err: unknown) => {
        assert.ok(err instanceof PurchaseOrderMutationError);
        assert.equal((err as PurchaseOrderMutationError).code, "invalid_response");
        return true;
      },
    );
  });
});

describe("submitPurchaseOrderForApproval", () => {
  test("maps camelCase input to p_ RPC params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_PO_ROW, status: "submitted" }, error: null }, calls);

    const po = await submitPurchaseOrderForApproval(client, { purchaseOrderId: PO_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff" });

    assert.equal(calls[0]?.fn, "submit_purchase_order_for_approval");
    assert.equal(calls[0]?.args.p_purchase_order_id, PO_ID);
    assert.equal(po.status, "submitted");
  });
});

describe("issuePurchaseOrder", () => {
  test("classifies a purchase_order_approval_pending error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "purchase_order_approval_pending: purchase order 923e... approval_status is pending" } }, []);
    await assert.rejects(
      () => issuePurchaseOrder(client, { purchaseOrderId: PO_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (err: unknown) => {
        assert.ok(err instanceof PurchaseOrderMutationError);
        assert.equal((err as PurchaseOrderMutationError).code, "purchase_order_approval_pending");
        return true;
      },
    );
  });
});

describe("amendPurchaseOrder", () => {
  test("rejects an empty reason before ever calling the RPC", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_PO_ROW, error: null }, calls);

    await assert.rejects(() =>
      amendPurchaseOrder(client, { purchaseOrderId: PO_ID, expectedVersion: 1, reason: "", idempotencyKey: "idem-amend-1", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies a fulfillment_in_progress error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "fulfillment_in_progress: purchase order 923e... has fulfillment_status partial" } }, []);
    await assert.rejects(
      () => amendPurchaseOrder(client, { purchaseOrderId: PO_ID, expectedVersion: 1, reason: "price change", idempotencyKey: "idem-amend-2", actorAuthUserId: ACTOR_ID, actorLabel: "staff" }),
      (err: unknown) => {
        assert.ok(err instanceof PurchaseOrderMutationError);
        assert.equal((err as PurchaseOrderMutationError).code, "fulfillment_in_progress");
        return true;
      },
    );
  });
});

describe("cancelPurchaseOrder", () => {
  test("maps camelCase input to p_ RPC params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_PO_ROW, status: "cancelled" }, error: null }, calls);

    const po = await cancelPurchaseOrder(client, { purchaseOrderId: PO_ID, expectedVersion: 1, reason: "vendor withdrew", actorAuthUserId: ACTOR_ID, actorLabel: "staff" });

    assert.equal(calls[0]?.fn, "cancel_purchase_order");
    assert.equal(calls[0]?.args.p_reason, "vendor withdrew");
    assert.equal(po.status, "cancelled");
  });
});
