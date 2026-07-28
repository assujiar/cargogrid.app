import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { recordTransactionLineageOverride, backfillTransactionLineage, TransactionLineageMutationError, type TransactionLineageMutationRpcClient } from "./transaction-lineage.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "223e4567-e89b-12d3-a456-426614174000";
const SHIPMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";
const EDGE_ID = "523e4567-e89b-12d3-a456-426614174000";

function recordingClient(response: { data: unknown; error: { message: string } | null }): {
  client: TransactionLineageMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TransactionLineageMutationRpcClient;
  return { client, calls };
}

describe("recordTransactionLineageOverride", () => {
  const edgeRow = {
    id: EDGE_ID,
    tenant_id: TENANT_ID,
    relation_type: "job_to_shipment",
    source_type: "job_order",
    source_id: JOB_ORDER_ID,
    target_type: "shipment_order",
    target_id: SHIPMENT_ID,
    source_version_hash: null,
    owner_user_id: null,
    org_unit_id: null,
    is_override: true,
    override_reason: "consolidation correction",
    created_by_auth_user_id: ACTOR_ID,
    created_by_label: "rep",
    created_at: "2026-07-28T00:00:00Z",
  };

  test("calls record_transaction_lineage_override with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: edgeRow, error: null });
    const edge = await recordTransactionLineageOverride(client, {
      tenantId: TENANT_ID,
      relationType: "job_to_shipment",
      sourceType: "job_order",
      sourceId: JOB_ORDER_ID,
      targetType: "shipment_order",
      targetId: SHIPMENT_ID,
      reason: "consolidation correction",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(calls[0]?.fn, "record_transaction_lineage_override");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_relation_type: "job_to_shipment",
      p_source_type: "job_order",
      p_source_id: JOB_ORDER_ID,
      p_target_type: "shipment_order",
      p_target_id: SHIPMENT_ID,
      p_reason: "consolidation correction",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(edge.isOverride, true);
  });

  test("classifies a known error code", async () => {
    const { client } = recordingClient({ data: null, error: { message: "transaction_lineage_edge_already_recorded: an edge already exists" } });
    await assert.rejects(
      () =>
        recordTransactionLineageOverride(client, {
          tenantId: TENANT_ID,
          relationType: "job_to_shipment",
          sourceType: "job_order",
          sourceId: JOB_ORDER_ID,
          targetType: "shipment_order",
          targetId: SHIPMENT_ID,
          reason: "redundant",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => {
        assert.ok(err instanceof TransactionLineageMutationError);
        assert.equal((err as TransactionLineageMutationError).code, "transaction_lineage_edge_already_recorded");
        return true;
      },
    );
  });

  test("rejects an empty reason before the RPC is even called", async () => {
    const { client, calls } = recordingClient({ data: edgeRow, error: null });
    await assert.rejects(() =>
      recordTransactionLineageOverride(client, {
        tenantId: TENANT_ID,
        relationType: "job_to_shipment",
        sourceType: "job_order",
        sourceId: JOB_ORDER_ID,
        targetType: "shipment_order",
        targetId: SHIPMENT_ID,
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
    assert.equal(calls.length, 0);
  });
});

describe("backfillTransactionLineage", () => {
  test("calls backfill_transaction_lineage with the exact snake_case params and returns the numeric count", async () => {
    const { client, calls } = recordingClient({ data: 3, error: null });
    const count = await backfillTransactionLineage(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "backfill_transaction_lineage");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(count, 3);
  });

  test("rejects a non-numeric response", async () => {
    const { client } = recordingClient({ data: null, error: null });
    await assert.rejects(() => backfillTransactionLineage(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }), (err: unknown) => err instanceof TransactionLineageMutationError);
  });
});
