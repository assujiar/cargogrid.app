import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getTransactionLineage,
  detectTransactionLineageAnomalies,
  TransactionLineageQueryError,
  TransactionLineageQueryTimeoutError,
  type TransactionLineageQueryRpcClient,
} from "./transaction-lineage.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "423e4567-e89b-12d3-a456-426614174000";

function recordingClient(response: { data: unknown; error: { message: string } | null }): {
  client: TransactionLineageQueryRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TransactionLineageQueryRpcClient;
  return { client, calls };
}

describe("getTransactionLineage", () => {
  const manifestPayload = {
    jobOrderId: JOB_ORDER_ID,
    jobNumber: "JOB-2026-000001",
    sourceHandoffId: HANDOFF_ID,
    sourceQuotationId: null,
    sourcePayloadHash: null,
    shipments: [],
    profitability: null,
    billingReadiness: null,
    edges: [],
  };

  test("calls get_transaction_lineage with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: manifestPayload, error: null });
    const manifest = await getTransactionLineage(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(calls[0]?.fn, "get_transaction_lineage");
    assert.deepEqual(calls[0]?.args, { p_job_order_id: JOB_ORDER_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(manifest.jobOrderId, JOB_ORDER_ID);
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "job_order_not_found: x" } });
    await assert.rejects(() => getTransactionLineage(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID }), (err: unknown) => err instanceof TransactionLineageQueryError);
  });

  test("rejects with TransactionLineageQueryTimeoutError once the query budget elapses", async () => {
    const client = {
      rpc() {
        return new Promise(() => {
          // Deliberately never resolves -- proves the budget timer, not the RPC, wins.
        });
      },
    } as unknown as TransactionLineageQueryRpcClient;
    await assert.rejects(
      () => getTransactionLineage(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID }, { budgetMs: 10 }),
      (err: unknown) => {
        assert.ok(err instanceof TransactionLineageQueryTimeoutError);
        assert.match((err as Error).message, /get_transaction_lineage/);
        return true;
      },
    );
  });
});

describe("detectTransactionLineageAnomalies", () => {
  test("calls detect_transaction_lineage_anomalies with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({
      data: [{ anomaly_type: "orphan_shipment_order", relation_type: "job_to_shipment", target_type: "shipment_order", target_id: JOB_ORDER_ID, detail: "no edge" }],
      error: null,
    });
    const anomalies = await detectTransactionLineageAnomalies(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(calls[0]?.fn, "detect_transaction_lineage_anomalies");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(anomalies[0]?.anomalyType, "orphan_shipment_order");
  });

  test("rejects with a non-array result", async () => {
    const { client } = recordingClient({ data: { not: "an array" }, error: null });
    await assert.rejects(() => detectTransactionLineageAnomalies(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }), (err: unknown) => err instanceof TransactionLineageQueryError);
  });
});
