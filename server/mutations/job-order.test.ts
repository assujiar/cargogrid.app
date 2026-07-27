import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { prepareJobOrder, confirmJobOrder, overrideJobOrderField, JobOrderMutationError, type JobOrderMutationRpcClient } from "./job-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "423e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: JobOrderMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as JobOrderMutationRpcClient;
  return { client, calls };
}

const BASE_ROW = {
  id: JOB_ORDER_ID,
  tenant_id: TENANT_ID,
  job_number: "JOB-2026-000001",
  source_handoff_id: HANDOFF_ID,
  quotation_id: QUOTATION_ID,
  account_id: ACCOUNT_ID,
  customer_snapshot: { accountId: ACCOUNT_ID, customerSnapshot: { legal_name: "Ops Test Co" }, contactPhone: "0811" },
  cargo_service_snapshot: { service_type: "ocean_freight" },
  revenue_snapshot: { currency: "IDR", totalAmount: 15000000 },
  contract_snapshot: null,
  credit_snapshot: null,
  acceptance_snapshot: { decision: "accepted" },
  status: "draft",
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("prepareJobOrder", () => {
  test("calls prepare_job_order with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    const jobOrder = await prepareJobOrder(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });

    assert.equal(calls[0]?.fn, "prepare_job_order");
    assert.deepEqual(calls[0]?.args, { p_source_handoff_id: HANDOFF_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(jobOrder.status, "draft");
    assert.equal(jobOrder.revenueMasked, false);
  });

  test("classifies handoff_payload_unavailable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "handoff_payload_unavailable: handoff carries no payload to convert" } });
    await assert.rejects(
      () => prepareJobOrder(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof JobOrderMutationError);
        assert.equal(err.code, "handoff_payload_unavailable");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () => prepareJobOrder(client, { sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof JobOrderMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("confirmJobOrder", () => {
  test("calls confirm_job_order with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...BASE_ROW, status: "confirmed", record_version: 2 }, error: null });
    const jobOrder = await confirmJobOrder(client, { jobOrderId: JOB_ORDER_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });

    assert.equal(calls[0]?.fn, "confirm_job_order");
    assert.deepEqual(calls[0]?.args, { p_job_order_id: JOB_ORDER_ID, p_expected_version: 1, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(jobOrder.status, "confirmed");
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: job order expected version 1 but found 2" } });
    await assert.rejects(
      () => confirmJobOrder(client, { jobOrderId: JOB_ORDER_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof JobOrderMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });

  test("classifies invalid_transition (a second confirm on an already-confirmed order)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: job order is confirmed and cannot be confirmed" } });
    await assert.rejects(
      () => confirmJobOrder(client, { jobOrderId: JOB_ORDER_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof JobOrderMutationError);
        assert.equal(err.code, "invalid_transition");
        return true;
      },
    );
  });
});

describe("overrideJobOrderField", () => {
  test("calls override_job_order_field with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({
      data: { ...BASE_ROW, customer_snapshot: { ...BASE_ROW.customer_snapshot, contactPhone: "0899" }, record_version: 2 },
      error: null,
    });
    const jobOrder = await overrideJobOrderField(client, {
      jobOrderId: JOB_ORDER_ID,
      expectedVersion: 1,
      snapshotColumn: "customer_snapshot",
      fieldPath: "contactPhone",
      newValue: "0899",
      reason: "customer provided a new phone number",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });

    assert.equal(calls[0]?.fn, "override_job_order_field");
    assert.deepEqual(calls[0]?.args, {
      p_job_order_id: JOB_ORDER_ID,
      p_expected_version: 1,
      p_snapshot_column: "customer_snapshot",
      p_field_path: "contactPhone",
      p_new_value: "0899",
      p_reason: "customer provided a new phone number",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal((jobOrder.customerSnapshot as { contactPhone: string }).contactPhone, "0899");
  });

  test("rejects an empty reason before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    await assert.rejects(() =>
      overrideJobOrderField(client, {
        jobOrderId: JOB_ORDER_ID,
        expectedVersion: 1,
        snapshotColumn: "customer_snapshot",
        fieldPath: "contactPhone",
        newValue: "0899",
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
    assert.equal(calls.length, 0);
  });

  test("classifies override_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "override_reason_required: a non-empty reason is required" } });
    await assert.rejects(
      () =>
        overrideJobOrderField(client, {
          jobOrderId: JOB_ORDER_ID,
          expectedVersion: 1,
          snapshotColumn: "customer_snapshot",
          fieldPath: "contactPhone",
          newValue: "0899",
          reason: "x",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof JobOrderMutationError);
        assert.equal(err.code, "override_reason_required");
        return true;
      },
    );
  });

  test("rejects a financial-column override attempt at the schema layer, before ever calling the RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: BASE_ROW, error: null });
    await assert.rejects(() =>
      overrideJobOrderField(client, {
        jobOrderId: JOB_ORDER_ID,
        expectedVersion: 1,
        // deliberately cast past the contract's own compile-time enum guard -- proves the
        // zod schema itself is the real gate, not just the type system
        snapshotColumn: "revenue_snapshot" as never,
        fieldPath: "totalAmount",
        newValue: 99,
        reason: "attempted financial edit",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
    assert.equal(calls.length, 0);
  });
});
