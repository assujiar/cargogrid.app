import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createWarehouseBillingRateComponent,
  getEffectiveWarehouseBillingRate,
  captureWarehouseBillingEvent,
  calculateWarehouseBillingEvent,
  recalculateWarehouseBillingEvent,
  holdWarehouseBillingEvent,
  releaseWarehouseBillingEventHold,
  reviewWarehouseBillingEvent,
  approveWarehouseBillingEvent,
  handoffWarehouseBillingEvent,
  recordWarehouseBillingReconciliationOutcome,
  correctWarehouseBillingEvent,
  reverseWarehouseBillingEvent,
  previewWarehouseBillingCalculation,
  WarehouseBillingMutationError,
  type WarehouseBillingMutationRpcClient,
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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WarehouseBillingMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WarehouseBillingMutationRpcClient;
  return { client, calls };
}

const RATE_COMPONENT_ROW = {
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
};

const EVENT_ROW = {
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
};

const HANDOFF_ROW = {
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
};

describe("createWarehouseBillingRateComponent", () => {
  test("calls create_warehouse_billing_rate_component with p_-prefixed args", async () => {
    const { client, calls } = fakeRpcClient({ data: [RATE_COMPONENT_ROW], error: null });
    const row = await createWarehouseBillingRateComponent(client, {
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
    assert.equal(calls[0]?.fn, "create_warehouse_billing_rate_component");
    assert.equal(calls[0]?.args.p_contract_id, CONTRACT_ID);
    assert.equal(calls[0]?.args.p_rate_basis, "per_unit");
    assert.equal(row.id, RATE_COMPONENT_ID);
  });

  test("classifies a rate_component_requires_draft_contract error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "rate_component_requires_draft_contract: contract is published" } });
    await assert.rejects(
      () =>
        createWarehouseBillingRateComponent(client, {
          contractId: CONTRACT_ID,
          activityType: "storage",
          rateBasis: "flat",
          unitRate: 100,
          currency: "IDR",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "rate_component_requires_draft_contract");
        return true;
      },
    );
  });

  test("classifies an unrecognized error message as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unclassified_db_error: oops" } });
    await assert.rejects(
      () =>
        createWarehouseBillingRateComponent(client, {
          contractId: CONTRACT_ID,
          activityType: "storage",
          rateBasis: "flat",
          unitRate: 100,
          currency: "IDR",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("getEffectiveWarehouseBillingRate", () => {
  test("classifies no_effective_rate", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "no_effective_rate: no published contract covers this" } });
    await assert.rejects(
      () =>
        getEffectiveWarehouseBillingRate(client, {
          tenantId: TENANT_ID,
          accountId: ACCOUNT_ID,
          warehouseId: WAREHOUSE_ID,
          activityType: "putaway",
          asOf: "2026-08-04T00:00:00.000Z",
          actorAuthUserId: ACTOR_ID,
        }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "no_effective_rate");
        return true;
      },
    );
  });
});

describe("captureWarehouseBillingEvent", () => {
  test("sends every field with the right p_ prefix, including null-coalesced optionals", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    await captureWarehouseBillingEvent(client, {
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      ownerAccountId: ACCOUNT_ID,
      activityType: "putaway",
      sourceType: "wms_putaway_confirmation",
      sourceId: SOURCE_ID,
      quantity: 10,
      uomCode: "PCS",
      activityDate: "2026-08-04T00:00:00.000Z",
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_warehouse_id: WAREHOUSE_ID,
      p_owner_account_id: ACCOUNT_ID,
      p_activity_type: "putaway",
      p_source_type: "wms_putaway_confirmation",
      p_source_id: SOURCE_ID,
      p_quantity: 10,
      p_uom_code: "PCS",
      p_activity_date: "2026-08-04T00:00:00.000Z",
      p_idempotency_key: "idem-1",
      p_correction_reason: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
  });

  test("classifies source_already_captured", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "source_already_captured: wms_receipt_line x already has an active billing event" } });
    await assert.rejects(
      () =>
        captureWarehouseBillingEvent(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          ownerAccountId: ACCOUNT_ID,
          activityType: "receiving",
          sourceType: "wms_receipt_line",
          sourceId: SOURCE_ID,
          quantity: 10,
          uomCode: "PCS",
          activityDate: "2026-08-04T00:00:00.000Z",
          idempotencyKey: "idem-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "source_already_captured");
        return true;
      },
    );
  });

  test("classifies idempotency_key_conflict distinctly from source_already_captured", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "idempotency_key_conflict: idempotency key was already used for a different capture" } });
    await assert.rejects(
      () =>
        captureWarehouseBillingEvent(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          ownerAccountId: ACCOUNT_ID,
          activityType: "receiving",
          sourceType: "wms_receipt_line",
          sourceId: SOURCE_ID,
          quantity: 10,
          uomCode: "PCS",
          activityDate: "2026-08-04T00:00:00.000Z",
          idempotencyKey: "idem-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "idempotency_key_conflict");
        return true;
      },
    );
  });
});

describe("calculateWarehouseBillingEvent / recalculateWarehouseBillingEvent", () => {
  test("calculate defaults p_tax_code to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [EVENT_ROW], error: null });
    await calculateWarehouseBillingEvent(client, { eventId: EVENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.args.p_tax_code, null);
  });

  test("recalculate rejects an already_calculated-shaped error passthrough as check", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: billing event x is approved -- only pending_review or reviewed may be recalculated" } });
    await assert.rejects(
      () => recalculateWarehouseBillingEvent(client, { eventId: EVENT_ID, expectedVersion: 2, reason: "corrected uom", actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("hold / release / review / approve", () => {
  test("hold sends the reason through", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EVENT_ROW, status: "on_hold" }], error: null });
    await holdWarehouseBillingEvent(client, { eventId: EVENT_ID, reason: "customer dispute", expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(calls[0]?.args.p_reason, "customer dispute");
  });

  test("release-hold call shape has no reason parameter", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EVENT_ROW, status: "pending_review" }], error: null });
    await releaseWarehouseBillingEventHold(client, { eventId: EVENT_ID, expectedVersion: 3, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.deepEqual(Object.keys(calls[0]?.args ?? {}).sort(), ["p_actor_auth_user_id", "p_actor_label", "p_event_id", "p_expected_version"]);
  });

  test("approve classifies self_approval_not_allowed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_allowed: identity x reviewed billing event y and may not also approve it" } });
    await assert.rejects(
      () => approveWarehouseBillingEvent(client, { eventId: EVENT_ID, expectedVersion: 4, actorAuthUserId: ACTOR_ID, actorLabel: "reviewer" }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "self_approval_not_allowed");
        return true;
      },
    );
  });

  test("review calls review_warehouse_billing_event", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EVENT_ROW, status: "reviewed" }], error: null });
    await reviewWarehouseBillingEvent(client, { eventId: EVENT_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(calls[0]?.fn, "review_warehouse_billing_event");
  });
});

describe("handoffWarehouseBillingEvent", () => {
  test("parses the returned handoff row", async () => {
    const { client } = fakeRpcClient({ data: [HANDOFF_ROW], error: null });
    const handoff = await handoffWarehouseBillingEvent(client, { eventId: EVENT_ID, idempotencyKey: "idem-handoff-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(handoff.id, HANDOFF_ID);
  });
});

describe("recordWarehouseBillingReconciliationOutcome", () => {
  test("calls the RPC with p_status/p_note", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...HANDOFF_ROW, reconciliation_status: "reconciled", reconciliation_note: "matched", reconciled_at: "2026-08-05T00:00:00.000Z" }], error: null });
    await recordWarehouseBillingReconciliationOutcome(client, { handoffId: HANDOFF_ID, status: "reconciled", note: "matched", actorAuthUserId: ACTOR_ID, actorLabel: "finance-worker" });
    assert.equal(calls[0]?.fn, "record_warehouse_billing_reconciliation_outcome");
    assert.equal(calls[0]?.args.p_status, "reconciled");
    assert.equal(calls[0]?.args.p_note, "matched");
  });

  test("classifies reconciliation_outcome_conflict", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reconciliation_outcome_conflict: handoff x already has reconciliation_status reconciled" } });
    await assert.rejects(
      () => recordWarehouseBillingReconciliationOutcome(client, { handoffId: HANDOFF_ID, status: "rejected", note: "retry", actorAuthUserId: ACTOR_ID, actorLabel: "finance-worker" }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "reconciliation_outcome_conflict");
        return true;
      },
    );
  });
});

describe("correctWarehouseBillingEvent / reverseWarehouseBillingEvent", () => {
  test("correct sends the new quantity through as p_new_quantity", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...EVENT_ROW, quantity: "8", corrects_event_id: EVENT_ID }], error: null });
    await correctWarehouseBillingEvent(client, { originalEventId: EVENT_ID, expectedVersion: 1, newQuantity: 8, reason: "recount", idempotencyKey: "idem-correct-1", actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(calls[0]?.fn, "correct_warehouse_billing_event");
    assert.equal(calls[0]?.args.p_new_quantity, 8);
  });

  test("correct classifies already_corrected", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "already_corrected: billing event x already has a correcting event" } });
    await assert.rejects(
      () => correctWarehouseBillingEvent(client, { originalEventId: EVENT_ID, expectedVersion: 1, newQuantity: 5, reason: "recount", idempotencyKey: "idem-correct-2", actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "already_corrected");
        return true;
      },
    );
  });

  test("reverse classifies already_reversed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "already_reversed: billing event x already has a reversing event" } });
    await assert.rejects(
      () => reverseWarehouseBillingEvent(client, { originalEventId: EVENT_ID, expectedVersion: 1, reason: "duplicate charge", idempotencyKey: "idem-reverse-1", actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "already_reversed");
        return true;
      },
    );
  });
});

describe("previewWarehouseBillingCalculation", () => {
  test("returns the parsed breakdown object (not an array-wrapped row)", async () => {
    const { client, calls } = fakeRpcClient({
      data: {
        contractId: CONTRACT_ID,
        rateComponentId: RATE_COMPONENT_ID,
        baseAmount: 15000,
        taxCode: null,
        taxAmount: 0,
        taxRuleVersionId: null,
        totalAmount: 15000,
        currency: "IDR",
        roundingMode: "round_half_up",
        calculationExplanation: { rateBasis: "per_unit" },
      },
      error: null,
    });
    const preview = await previewWarehouseBillingCalculation(client, {
      tenantId: TENANT_ID,
      accountId: ACCOUNT_ID,
      warehouseId: WAREHOUSE_ID,
      activityType: "putaway",
      quantity: 10,
      uomCode: "PCS",
      asOf: "2026-08-04T00:00:00.000Z",
      actorAuthUserId: ACTOR_ID,
    });
    assert.equal(calls[0]?.fn, "preview_warehouse_billing_calculation");
    assert.equal(preview.totalAmount, 15000);
  });

  test("throws invalid_response when the RPC returns a non-object", async () => {
    const { client } = fakeRpcClient({ data: "not-an-object", error: null });
    await assert.rejects(
      () =>
        previewWarehouseBillingCalculation(client, {
          tenantId: TENANT_ID,
          accountId: ACCOUNT_ID,
          warehouseId: WAREHOUSE_ID,
          activityType: "putaway",
          quantity: 10,
          uomCode: "PCS",
          asOf: "2026-08-04T00:00:00.000Z",
          actorAuthUserId: ACTOR_ID,
        }),
      (err: unknown) => {
        assert.ok(err instanceof WarehouseBillingMutationError);
        assert.equal(err.code, "invalid_response");
        return true;
      },
    );
  });
});
