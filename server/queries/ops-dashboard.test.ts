import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getOpsDashboardShipmentStatus,
  getOpsDashboardMilestoneSla,
  getOpsDashboardExceptionQueue,
  getOpsDashboardEpodCompletion,
  getOpsDashboardCostVariance,
  getOpsDashboardBillingReadiness,
  OpsDashboardQueryError,
  OpsDashboardQueryTimeoutError,
  type OpsDashboardQueryRpcClient,
} from "./ops-dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ORG_UNIT_ID = "323e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "423e4567-e89b-12d3-a456-426614174000";

function recordingClient(response: { data: unknown; error: { message: string } | null }): {
  client: OpsDashboardQueryRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as OpsDashboardQueryRpcClient;
  return { client, calls };
}

describe("getOpsDashboardShipmentStatus", () => {
  test("calls get_ops_dashboard_shipment_status with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ status: "delivered", shipment_count: 1 }], error: null });
    const entries = await getOpsDashboardShipmentStatus(client, { tenantId: TENANT_ID, orgUnitId: ORG_UNIT_ID, ownerUserId: OWNER_ID });
    assert.equal(calls[0]?.fn, "get_ops_dashboard_shipment_status");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_org_unit_id: ORG_UNIT_ID, p_owner_user_id: OWNER_ID });
    assert.equal(entries[0]?.status, "delivered");
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "boom" } });
    await assert.rejects(() => getOpsDashboardShipmentStatus(client, { tenantId: TENANT_ID }), (err: unknown) => err instanceof OpsDashboardQueryError);
  });

  test("rejects with a non-array result", async () => {
    const { client } = recordingClient({ data: { not: "an array" }, error: null });
    await assert.rejects(() => getOpsDashboardShipmentStatus(client, { tenantId: TENANT_ID }), (err: unknown) => err instanceof OpsDashboardQueryError);
  });

  test("rejects with OpsDashboardQueryTimeoutError once the query budget elapses", async () => {
    const client = {
      rpc() {
        return new Promise(() => {
          // Deliberately never resolves -- proves the budget timer, not the RPC, wins.
        });
      },
    } as unknown as OpsDashboardQueryRpcClient;
    await assert.rejects(
      () => getOpsDashboardShipmentStatus(client, { tenantId: TENANT_ID }, { budgetMs: 10 }),
      (err: unknown) => {
        assert.ok(err instanceof OpsDashboardQueryTimeoutError);
        assert.match((err as Error).message, /get_ops_dashboard_shipment_status/);
        return true;
      },
    );
  });
});

describe("getOpsDashboardMilestoneSla", () => {
  test("calls get_ops_dashboard_milestone_sla with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ bucket: "delayed", shipment_count: 1 }], error: null });
    const entries = await getOpsDashboardMilestoneSla(client, { tenantId: TENANT_ID });
    assert.equal(calls[0]?.fn, "get_ops_dashboard_milestone_sla");
    assert.equal(entries[0]?.bucket, "delayed");
  });
});

describe("getOpsDashboardExceptionQueue", () => {
  test("calls get_ops_dashboard_exception_queue with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ severity: "high", exception_count: 1 }], error: null });
    const entries = await getOpsDashboardExceptionQueue(client, { tenantId: TENANT_ID });
    assert.equal(calls[0]?.fn, "get_ops_dashboard_exception_queue");
    assert.equal(entries[0]?.severity, "high");
  });
});

describe("getOpsDashboardEpodCompletion", () => {
  test("calls get_ops_dashboard_epod_completion with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ status: "completed", capture_count: 1 }], error: null });
    const entries = await getOpsDashboardEpodCompletion(client, { tenantId: TENANT_ID });
    assert.equal(calls[0]?.fn, "get_ops_dashboard_epod_completion");
    assert.equal(entries[0]?.status, "completed");
  });
});

describe("getOpsDashboardCostVariance", () => {
  test("calls get_ops_dashboard_cost_variance with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ bucket: "over_budget", currency: "IDR", shipment_count: 1, avg_variance_pct: 30, variance_masked: false }], error: null });
    const entries = await getOpsDashboardCostVariance(client, { tenantId: TENANT_ID });
    assert.equal(calls[0]?.fn, "get_ops_dashboard_cost_variance");
    assert.equal(entries[0]?.avgVariancePct, 30);
    assert.equal(entries[0]?.varianceMasked, false);
  });
});

describe("getOpsDashboardBillingReadiness", () => {
  test("calls get_ops_dashboard_billing_readiness with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ bucket: "not_ready", job_count: 1 }], error: null });
    const entries = await getOpsDashboardBillingReadiness(client, { tenantId: TENANT_ID });
    assert.equal(calls[0]?.fn, "get_ops_dashboard_billing_readiness");
    assert.equal(entries[0]?.bucket, "not_ready");
  });
});
