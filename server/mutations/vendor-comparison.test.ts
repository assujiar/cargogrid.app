import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createVendorComparison,
  reviseVendorComparison,
  recommendVendorComparisonOffer,
  submitVendorComparisonForApproval,
  VendorComparisonMutationError,
  type VendorComparisonMutationRpcClient,
} from "./vendor-comparison.ts";

const COMPARISON_ID = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RFQ_ID = "423e4567-e89b-12d3-a456-426614174000";
const OFFER_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

const VALID_COMPARISON_ROW = {
  id: COMPARISON_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  rfq_id: RFQ_ID,
  sourcing_request_id: "523e4567-e89b-12d3-a456-426614174000",
  version: 1,
  revised_from_id: null,
  comparison_currency: "IDR",
  basis_weight: 5000,
  basis_volume: null,
  basis_quantity: 1,
  criteria_snapshot: [{ key: "price", label: "Price", weight: 100 }],
  status: "draft",
  recommended_offer_id: null,
  recommended_reason: null,
  recommended_at: null,
  selected_offer_id: null,
  selection_reason: null,
  submitted_at: null,
  submitted_by: null,
  idempotency_key: "idem-1",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): VendorComparisonMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorComparisonMutationRpcClient;
}

describe("createVendorComparison", () => {
  test("maps camelCase input to p_ RPC params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_COMPARISON_ROW, error: null }, calls);

    const comparison = await createVendorComparison(client, {
      tenantId: TENANT_ID,
      rfqId: RFQ_ID,
      comparisonCurrency: "IDR",
      idempotencyKey: "idem-create-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "reviewer",
    });

    assert.equal(calls[0]?.fn, "create_vendor_comparison");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(calls[0]?.args.p_rfq_id, RFQ_ID);
    assert.equal(calls[0]?.args.p_comparison_currency, "IDR");
    assert.equal(comparison.id, COMPARISON_ID);
  });

  test("classifies a known error prefix (invalid_source_status) into its code", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "invalid_source_status: rfq 423e... is draft" } }, []);
    await assert.rejects(
      () =>
        createVendorComparison(client, {
          tenantId: TENANT_ID,
          rfqId: RFQ_ID,
          comparisonCurrency: "IDR",
          idempotencyKey: "idem-create-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "reviewer",
        }),
      (err: unknown) => {
        assert.ok(err instanceof VendorComparisonMutationError);
        assert.equal((err as VendorComparisonMutationError).code, "invalid_source_status");
        return true;
      },
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "totally_unexpected_error: something broke" } }, []);
    await assert.rejects(
      () =>
        createVendorComparison(client, {
          tenantId: TENANT_ID,
          rfqId: RFQ_ID,
          comparisonCurrency: "IDR",
          idempotencyKey: "idem-create-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "reviewer",
        }),
      (err: unknown) => {
        assert.ok(err instanceof VendorComparisonMutationError);
        assert.equal((err as VendorComparisonMutationError).code, "mutation_failed");
        return true;
      },
    );
  });

  test("throws invalid_response when the RPC returns no row and no error", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    await assert.rejects(
      () =>
        createVendorComparison(client, {
          tenantId: TENANT_ID,
          rfqId: RFQ_ID,
          comparisonCurrency: "IDR",
          idempotencyKey: "idem-create-4",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "reviewer",
        }),
      (err: unknown) => {
        assert.ok(err instanceof VendorComparisonMutationError);
        assert.equal((err as VendorComparisonMutationError).code, "invalid_response");
        return true;
      },
    );
  });
});

describe("reviseVendorComparison", () => {
  test("rejects an empty reason before ever calling the RPC", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_COMPARISON_ROW, error: null }, calls);

    await assert.rejects(() =>
      reviseVendorComparison(client, {
        comparisonId: COMPARISON_ID,
        reason: "",
        idempotencyKey: "idem-revise-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "reviewer",
      }),
    );
    assert.equal(calls.length, 0);
  });
});

describe("recommendVendorComparisonOffer", () => {
  test("maps camelCase input to p_ RPC params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_COMPARISON_ROW, status: "recommended", recommended_offer_id: OFFER_ID }, error: null }, calls);

    const comparison = await recommendVendorComparisonOffer(client, {
      comparisonId: COMPARISON_ID,
      comparisonOfferId: OFFER_ID,
      reason: null,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "reviewer",
    });

    assert.equal(calls[0]?.fn, "recommend_vendor_comparison_offer");
    assert.equal(calls[0]?.args.p_comparison_offer_id, OFFER_ID);
    assert.equal(comparison.recommendedOfferId, OFFER_ID);
  });

  test("classifies a reason_required error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "reason_required: a non-empty reason is required to recommend an offer other than the lowest normalized cost" } }, []);
    await assert.rejects(
      () =>
        recommendVendorComparisonOffer(client, {
          comparisonId: COMPARISON_ID,
          comparisonOfferId: OFFER_ID,
          reason: null,
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "reviewer",
        }),
      (err: unknown) => {
        assert.ok(err instanceof VendorComparisonMutationError);
        assert.equal((err as VendorComparisonMutationError).code, "reason_required");
        return true;
      },
    );
  });
});

describe("submitVendorComparisonForApproval", () => {
  test("maps camelCase input to p_ RPC params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_COMPARISON_ROW, status: "submitted", selected_offer_id: OFFER_ID }, error: null }, calls);

    const comparison = await submitVendorComparisonForApproval(client, {
      comparisonId: COMPARISON_ID,
      selectedOfferId: OFFER_ID,
      selectionReason: null,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "approver",
    });

    assert.equal(calls[0]?.fn, "submit_vendor_comparison_for_approval");
    assert.equal(calls[0]?.args.p_selected_offer_id, OFFER_ID);
    assert.equal(comparison.status, "submitted");
    assert.equal(comparison.selectedOfferId, OFFER_ID);
  });
});
