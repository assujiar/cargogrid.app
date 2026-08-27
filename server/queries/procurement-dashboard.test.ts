// Track B Batch 3, ISS-2026-063: server/queries/procurement-dashboard.ts (PRC-266) had no
// dedicated test file, unlike every sibling dashboard query module (finance-dashboard.test.ts,
// ops-dashboard.test.ts, etc.). Mirrors finance-dashboard.test.ts's own established pattern:
// a recordingClient() stub, per-function RPC-arg-mapping/error-wrap/non-array-reject assertions,
// and a query-budget-timeout test proving the budget timer -- not the RPC -- wins.
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listActiveProcurementMetricDefinitions,
  listProcurementDashboardSavedViews,
  getProcurementDashboardVendorRiskSummary,
  listProcurementVendorRiskDashboardRows,
  getProcurementDashboardRateValiditySummary,
  getProcurementDashboardRateCompetitivenessSummary,
  getProcurementDashboardRfqCycleSummary,
  getProcurementDashboardCapacityReservationSummary,
  getProcurementDashboardAssignmentAcceptanceSummary,
  getProcurementDashboardPoSummary,
  getProcurementDashboardContractSummary,
  getProcurementDashboardPerformanceSummary,
  ProcurementDashboardQueryError,
  ProcurementDashboardQueryTimeoutError,
  type ProcurementDashboardQueryClient,
} from "./procurement-dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function recordingClient(response: { data: unknown; error: { message: string } | null }): {
  client: ProcurementDashboardQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ProcurementDashboardQueryClient;
  return { client, calls };
}

function recordingFromClient(response: { data: unknown; error: { message: string } | null }): {
  client: ProcurementDashboardQueryClient;
  calls: { table: string }[];
} {
  const calls: { table: string }[] = [];
  const chain = {
    eq() {
      return chain;
    },
    order() {
      return response;
    },
  };
  const client = {
    from(table: string) {
      calls.push({ table });
      return { select: () => chain };
    },
  } as unknown as ProcurementDashboardQueryClient;
  return { client, calls };
}

const SCOPE_FILTER = { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID };

describe("listActiveProcurementMetricDefinitions", () => {
  test("reads from procurement_metric_definitions, not an RPC", async () => {
    const { client, calls } = recordingFromClient({
      data: [
        {
          id: "923e4567-e89b-12d3-a456-426614174000",
          code: "vendor_risk_summary",
          metric_group: "vendor_risk_compliance",
          version_no: 1,
          is_current: true,
          supersedes_definition_id: null,
          name: "Vendor Risk Summary",
          description: null,
          source_tables: ["app.vendor_profiles"],
          source_columns: ["lifecycle_status"],
          formula: "count(*) group by lifecycle_status",
          grain: "tenant",
          freshness_rule: "live",
          required_action: "View",
          additional_mask_action: null,
          source_function: "app.get_procurement_dashboard_vendor_risk_summary",
          status: "active",
          registered_by: null,
          created_at: "2026-07-01T00:00:00Z",
        },
      ],
      error: null,
    });
    const rows = await listActiveProcurementMetricDefinitions(client);
    assert.equal(calls[0]?.table, "procurement_metric_definitions");
    assert.equal(rows[0]?.metricGroup, "vendor_risk_compliance");
  });

  test("wraps a query error", async () => {
    const { client } = recordingFromClient({ data: null, error: { message: "relation does not exist" } });
    await assert.rejects(() => listActiveProcurementMetricDefinitions(client), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("listProcurementDashboardSavedViews", () => {
  test("calls list_procurement_dashboard_saved_views with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({
      data: [
        {
          id: "623e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          owner_auth_user_id: ACTOR_ID,
          metric_group: "vendor_risk_compliance",
          name: "My View",
          description: null,
          filters: {},
          sort: {},
          record_version: 1,
          created_by: ACTOR_ID,
          created_at: "2026-08-01T00:00:00Z",
          updated_at: "2026-08-01T00:00:00Z",
        },
      ],
      error: null,
    });
    await listProcurementDashboardSavedViews(client, TENANT_ID, ACTOR_ID, "vendor_risk_compliance", 10, null, null);
    assert.equal(calls[0]?.fn, "list_procurement_dashboard_saved_views");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_metric_group: "vendor_risk_compliance", p_actor_auth_user_id: ACTOR_ID, p_limit: 10, p_cursor: null, p_cursor_id: null });
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => listProcurementDashboardSavedViews(client, TENANT_ID, ACTOR_ID), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardVendorRiskSummary", () => {
  test("calls get_procurement_dashboard_vendor_risk_summary with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({
      data: [{ lifecycle_status: "active", vendor_count: 5, compliance_hold_count: 1, band_excellent_count: 2, band_good_count: 2, band_watch_count: 1, band_poor_count: 0 }],
      error: null,
    });
    const rows = await getProcurementDashboardVendorRiskSummary(client, SCOPE_FILTER);
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_vendor_risk_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(rows[0]?.vendorCount, 5);
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardVendorRiskSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });

  test("rejects with a non-array result", async () => {
    const { client } = recordingClient({ data: { not: "an array" }, error: null });
    await assert.rejects(() => getProcurementDashboardVendorRiskSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });

  test("rejects with ProcurementDashboardQueryTimeoutError once the query budget elapses", async () => {
    const client = {
      rpc() {
        return new Promise(() => {
          // Deliberately never resolves -- proves the budget timer, not the RPC, wins.
        });
      },
    } as unknown as ProcurementDashboardQueryClient;
    await assert.rejects(
      () => getProcurementDashboardVendorRiskSummary(client, SCOPE_FILTER, { budgetMs: 10 }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementDashboardQueryTimeoutError);
        assert.match((err as Error).message, /get_procurement_dashboard_vendor_risk_summary/);
        return true;
      },
    );
  });
});

describe("listProcurementVendorRiskDashboardRows", () => {
  test("calls list_procurement_vendor_risk_dashboard_rows with the exact snake_case params, including both cursor columns", async () => {
    const { client, calls } = recordingClient({
      data: [
        {
          vendor_master_id: "723e4567-e89b-12d3-a456-426614174000",
          legal_name: "Acme Freight",
          vendor_category: "carrier",
          lifecycle_status: "active",
          compliance_hold: false,
          compliance_expiring_soon_count: 0,
          compliance_expired_count: 0,
          scorecard_band: "good",
          scorecard_composite_score: 82.5,
          scorecard_window_end: "2026-07-31",
          created_at: "2026-08-01T00:00:00Z",
        },
      ],
      error: null,
    });
    await listProcurementVendorRiskDashboardRows(client, { ...SCOPE_FILTER, lifecycleStatus: "active", complianceHoldOnly: true, band: "good", search: "acme", limit: 10, cursor: "2026-08-01T00:00:00Z", cursorId: "823e4567-e89b-12d3-a456-426614174000" });
    assert.equal(calls[0]?.fn, "list_procurement_vendor_risk_dashboard_rows");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_lifecycle_status: "active",
      p_compliance_hold_only: true,
      p_band: "good",
      p_search: "acme",
      p_limit: 10,
      p_cursor: "2026-08-01T00:00:00Z",
      p_cursor_id: "823e4567-e89b-12d3-a456-426614174000",
    });
  });

  test("defaults optional filters to null and limit to 25", async () => {
    const { client, calls } = recordingClient({ data: [], error: null });
    await listProcurementVendorRiskDashboardRows(client, SCOPE_FILTER);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_lifecycle_status: null,
      p_compliance_hold_only: null,
      p_band: null,
      p_search: null,
      p_limit: 25,
      p_cursor: null,
      p_cursor_id: null,
    });
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => listProcurementVendorRiskDashboardRows(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardRateValiditySummary", () => {
  test("calls get_procurement_dashboard_rate_validity_summary with the exact snake_case params, including p_as_of", async () => {
    const { client, calls } = recordingClient({ data: [{ currency: "USD", validity_bucket: "current", rate_count: 3 }], error: null });
    const rows = await getProcurementDashboardRateValiditySummary(client, { ...SCOPE_FILTER, asOf: "2026-08-01" });
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_rate_validity_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_as_of: "2026-08-01" });
    assert.equal(rows[0]?.validityBucket, "current");
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardRateValiditySummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardRateCompetitivenessSummary", () => {
  test("calls get_procurement_dashboard_rate_competitiveness_summary with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ competitiveness_band: "strong", vendor_count: 4, avg_score: 88.5 }], error: null });
    const rows = await getProcurementDashboardRateCompetitivenessSummary(client, SCOPE_FILTER);
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_rate_competitiveness_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(rows[0]?.competitivenessBand, "strong");
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardRateCompetitivenessSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardRfqCycleSummary", () => {
  test("calls get_procurement_dashboard_rfq_cycle_summary with the exact snake_case params, including window bounds", async () => {
    const { client, calls } = recordingClient({ data: [], error: null });
    await getProcurementDashboardRfqCycleSummary(client, { ...SCOPE_FILTER, windowStart: "2026-07-01", windowEnd: "2026-07-31" });
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_rfq_cycle_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_window_start: "2026-07-01", p_window_end: "2026-07-31" });
  });

  test("defaults window bounds to null", async () => {
    const { client, calls } = recordingClient({ data: [], error: null });
    await getProcurementDashboardRfqCycleSummary(client, SCOPE_FILTER);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_window_start: null, p_window_end: null });
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardRfqCycleSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardCapacityReservationSummary", () => {
  test("calls get_procurement_dashboard_capacity_reservation_summary with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [], error: null });
    await getProcurementDashboardCapacityReservationSummary(client, { ...SCOPE_FILTER, windowStart: "2026-07-01", windowEnd: "2026-07-31" });
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_capacity_reservation_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_window_start: "2026-07-01", p_window_end: "2026-07-31" });
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardCapacityReservationSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardAssignmentAcceptanceSummary", () => {
  test("calls get_procurement_dashboard_assignment_acceptance_summary with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [], error: null });
    await getProcurementDashboardAssignmentAcceptanceSummary(client, { ...SCOPE_FILTER, windowStart: "2026-07-01", windowEnd: "2026-07-31" });
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_assignment_acceptance_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_window_start: "2026-07-01", p_window_end: "2026-07-31" });
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardAssignmentAcceptanceSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardPoSummary", () => {
  test("calls get_procurement_dashboard_po_summary with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ status: "issued", currency: "USD", po_count: 3, committed_amount: "1500.00", cost_masked: false }], error: null });
    const rows = await getProcurementDashboardPoSummary(client, SCOPE_FILTER);
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_po_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(rows[0]?.poCount, 3);
    assert.equal(rows[0]?.committedAmount, 1500);
  });

  test("passes through a null committedAmount when cost is masked", async () => {
    const { client } = recordingClient({ data: [{ status: "issued", currency: "USD", po_count: 3, committed_amount: null, cost_masked: true }], error: null });
    const rows = await getProcurementDashboardPoSummary(client, SCOPE_FILTER);
    assert.equal(rows[0]?.committedAmount, null);
    assert.equal(rows[0]?.costMasked, true);
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardPoSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardContractSummary", () => {
  test("calls get_procurement_dashboard_contract_summary with the exact snake_case params, including p_as_of", async () => {
    const { client, calls } = recordingClient({ data: [{ status: "active", contract_count: 6, expiring_soon_count: 2 }], error: null });
    const rows = await getProcurementDashboardContractSummary(client, { ...SCOPE_FILTER, asOf: "2026-08-01" });
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_contract_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_as_of: "2026-08-01" });
    assert.equal(rows[0]?.expiringSoonCount, 2);
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardContractSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });
});

describe("getProcurementDashboardPerformanceSummary", () => {
  test("calls get_procurement_dashboard_performance_summary with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [], error: null });
    await getProcurementDashboardPerformanceSummary(client, SCOPE_FILTER);
    assert.equal(calls[0]?.fn, "get_procurement_dashboard_performance_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks PRC:View" } });
    await assert.rejects(() => getProcurementDashboardPerformanceSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });

  test("rejects with a non-array result", async () => {
    const { client } = recordingClient({ data: { not: "an array" }, error: null });
    await assert.rejects(() => getProcurementDashboardPerformanceSummary(client, SCOPE_FILTER), (err: unknown) => err instanceof ProcurementDashboardQueryError);
  });

  test("rejects with ProcurementDashboardQueryTimeoutError once the query budget elapses", async () => {
    const client = {
      rpc() {
        return new Promise(() => {
          // Deliberately never resolves -- proves the budget timer, not the RPC, wins.
        });
      },
    } as unknown as ProcurementDashboardQueryClient;
    await assert.rejects(
      () => getProcurementDashboardPerformanceSummary(client, SCOPE_FILTER, { budgetMs: 10 }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementDashboardQueryTimeoutError);
        assert.match((err as Error).message, /get_procurement_dashboard_performance_summary/);
        return true;
      },
    );
  });
});
