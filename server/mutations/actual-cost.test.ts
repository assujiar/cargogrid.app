import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createActualCostDraft,
  addActualCostComponent,
  removeActualCostComponent,
  submitActualCost,
  decideActualCost,
  createActualCostAdjustment,
  ActualCostMutationError,
  type ActualCostMutationRpcClient,
} from "./actual-cost.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const COST_ID = "523e4567-e89b-12d3-a456-426614174000";
const COMPONENT_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ActualCostMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ActualCostMutationRpcClient;
  return { client, calls };
}

const COST_ROW = {
  id: COST_ID,
  tenant_id: TENANT_ID,
  shipment_order_id: SHIPMENT_ID,
  version_number: 1,
  is_current: true,
  supersedes_version_id: null,
  status: "draft",
  currency: "IDR",
  estimated_amount: null,
  total_amount: 0,
  approved_by_auth_user_id: null,
  approved_at: null,
  rejection_reason: null,
  adjustment_reason: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

const COMPONENT_ROW = {
  id: COMPONENT_ID,
  tenant_id: TENANT_ID,
  actual_cost_id: COST_ID,
  category: "freight",
  source_type: "vendor",
  vendor_id: TENANT_ID,
  assignment_id: null,
  document_file_id: null,
  description: "Ocean freight",
  quantity: 1,
  uom: "shipment",
  rate: 9500000,
  minimum_charge: 10000000,
  surcharge: 250000,
  amount: 10250000,
  currency: "IDR",
  idempotency_key: "idem-1",
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
};

describe("createActualCostDraft", () => {
  test("calls create_actual_cost_draft with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: COST_ROW, error: null });
    const cost = await createActualCostDraft(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, currency: "IDR", estimatedAmount: 12000000, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "create_actual_cost_draft");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_shipment_order_id: SHIPMENT_ID,
      p_currency: "IDR",
      p_estimated_amount: 12000000,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(cost.status, "draft");
  });

  test("classifies actual_cost_already_exists", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actual_cost_already_exists: shipment order already has a current version" } });
    await assert.rejects(
      () => createActualCostDraft(client, { tenantId: TENANT_ID, shipmentOrderId: SHIPMENT_ID, currency: "IDR", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ActualCostMutationError);
        assert.equal(err.code, "actual_cost_already_exists");
        return true;
      },
    );
  });
});

describe("addActualCostComponent", () => {
  test("calls add_actual_cost_component with defaults for optional fields", async () => {
    const { client, calls } = fakeRpcClient({ data: COMPONENT_ROW, error: null });
    const component = await addActualCostComponent(client, {
      actualCostId: COST_ID,
      category: "freight",
      sourceType: "vendor",
      vendorId: TENANT_ID,
      quantity: 1,
      rate: 9500000,
      minimumCharge: 10000000,
      surcharge: 250000,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "add_actual_cost_component");
    assert.deepEqual(calls[0]?.args, {
      p_actual_cost_id: COST_ID,
      p_category: "freight",
      p_source_type: "vendor",
      p_vendor_id: TENANT_ID,
      p_assignment_id: null,
      p_document_file_id: null,
      p_description: null,
      p_quantity: 1,
      p_uom: null,
      p_rate: 9500000,
      p_minimum_charge: 10000000,
      p_surcharge: 250000,
      p_idempotency_key: "idem-1",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(component.amount, 10250000);
  });

  test("classifies actual_cost_vendor_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actual_cost_vendor_required: a vendor_id is required" } });
    await assert.rejects(
      () =>
        addActualCostComponent(client, {
          actualCostId: COST_ID,
          category: "freight",
          sourceType: "vendor",
          quantity: 1,
          rate: 9500000,
          idempotencyKey: "idem-1",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ActualCostMutationError);
        assert.equal(err.code, "actual_cost_vendor_required");
        return true;
      },
    );
  });
});

describe("removeActualCostComponent", () => {
  test("calls remove_actual_cost_component with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await removeActualCostComponent(client, { componentId: COMPONENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "remove_actual_cost_component");
    assert.deepEqual(calls[0]?.args, { p_component_id: COMPONENT_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
  });
});

describe("submitActualCost", () => {
  test("classifies actual_cost_no_components", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actual_cost_no_components: at least one cost component is required" } });
    await assert.rejects(
      () => submitActualCost(client, { actualCostId: COST_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ActualCostMutationError);
        assert.equal(err.code, "actual_cost_no_components");
        return true;
      },
    );
  });
});

describe("decideActualCost", () => {
  test("calls decide_actual_cost with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...COST_ROW, status: "approved" }, error: null });
    const cost = await decideActualCost(client, { actualCostId: COST_ID, decision: "approved", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "decide_actual_cost");
    assert.deepEqual(calls[0]?.args, {
      p_actual_cost_id: COST_ID,
      p_decision: "approved",
      p_reason: null,
      p_expected_version: 1,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(cost.status, "approved");
  });

  test("classifies actual_cost_rejection_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actual_cost_rejection_reason_required: a reason is required" } });
    await assert.rejects(
      () => decideActualCost(client, { actualCostId: COST_ID, decision: "rejected", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ActualCostMutationError);
        assert.equal(err.code, "actual_cost_rejection_reason_required");
        return true;
      },
    );
  });
});

describe("createActualCostAdjustment", () => {
  test("calls create_actual_cost_adjustment with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...COST_ROW, version_number: 2, supersedes_version_id: COST_ID }, error: null });
    const cost = await createActualCostAdjustment(client, { previousActualCostId: COST_ID, adjustmentReason: "vendor corrected invoice", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "create_actual_cost_adjustment");
    assert.deepEqual(calls[0]?.args, { p_previous_actual_cost_id: COST_ID, p_adjustment_reason: "vendor corrected invoice", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(cost.versionNumber, 2);
  });

  test("classifies invalid_transition when the previous version is not approved", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: actual cost is draft and cannot be adjusted" } });
    await assert.rejects(
      () => createActualCostAdjustment(client, { previousActualCostId: COST_ID, adjustmentReason: "reason", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof ActualCostMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});
