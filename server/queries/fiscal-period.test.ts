import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listFinanceFiscalPeriods,
  getFinancePeriodCloseReadiness,
  getFinancePeriodTransitionHistory,
  resolveFinancePeriodForDate,
  listFinancePeriodChecklistItems,
  FiscalPeriodQueryError,
  type FiscalPeriodQueryRpcClient,
  type FiscalPeriodChecklistTableClient,
} from "./fiscal-period.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const PERIOD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const PERIOD_ROW = {
  id: PERIOD_ID,
  calendar_id: "523e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  company_id: null,
  period_code: "2026-01",
  name: "2026-01",
  start_date: "2026-01-01",
  end_date: "2026-01-31",
  sequence_number: 1,
  status: "open",
  closed_at: null,
  closed_by: null,
  record_version: 1,
  created_by: "finance-manager",
  created_at: "2026-07-28T00:00:00.000Z",
  updated_at: "2026-07-28T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): FiscalPeriodQueryRpcClient & { calls: number } {
  let calls = 0;
  return {
    get calls() {
      return calls;
    },
    async rpc(_fn: string, _args: Record<string, unknown>) {
      calls += 1;
      return response;
    },
  } as unknown as FiscalPeriodQueryRpcClient & { calls: number };
}

describe("listFinanceFiscalPeriods", () => {
  test("maps every returned row to the FinanceFiscalPeriod contract shape, ordered as returned", async () => {
    const client = fakeClient({ data: [PERIOD_ROW], error: null });
    const periods = await listFinanceFiscalPeriods(client, { tenantId: TENANT_ID, companyId: null, calendarId: null, actorAuthUserId: ACTOR_ID });
    assert.equal(periods.length, 1);
    assert.equal(periods[0]?.periodCode, "2026-01");
  });

  test("wraps a database error into a typed FiscalPeriodQueryError", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(() => listFinanceFiscalPeriods(client, { tenantId: TENANT_ID, companyId: null, calendarId: null, actorAuthUserId: ACTOR_ID }), FiscalPeriodQueryError);
  });
});

describe("getFinancePeriodCloseReadiness", () => {
  test("parses a close-readiness result", async () => {
    const client = fakeClient({ data: { periodId: PERIOD_ID, status: "soft_closed", ready: false, unsatisfiedRequiredItems: ["ar_aging_reconciled"] }, error: null });
    const readiness = await getFinancePeriodCloseReadiness(client, PERIOD_ID, ACTOR_ID);
    assert.equal(readiness.ready, false);
  });
});

describe("getFinancePeriodTransitionHistory", () => {
  test("maps every transition row", async () => {
    const client = fakeClient({
      data: [{ id: "623e4567-e89b-12d3-a456-426614174000", period_id: PERIOD_ID, tenant_id: TENANT_ID, from_status: "none", to_status: "open", reason: null, actor_auth_user_id: ACTOR_ID, actor_label: "finance-manager", created_at: "2026-07-28T00:00:00.000Z" }],
      error: null,
    });
    const history = await getFinancePeriodTransitionHistory(client, PERIOD_ID, ACTOR_ID);
    assert.equal(history.length, 1);
    assert.equal(history[0]?.toStatus, "open");
  });
});

describe("listFinancePeriodChecklistItems", () => {
  function fakeTableClient(rows: unknown[]): FiscalPeriodChecklistTableClient {
    const chain = {
      select: () => chain,
      eq: () => chain,
      order: async () => ({ data: rows, error: null }),
    };
    return { from: () => chain } as unknown as FiscalPeriodChecklistTableClient;
  }

  test("maps every checklist-item row", async () => {
    const client = fakeTableClient([
      { id: "723e4567-e89b-12d3-a456-426614174000", period_id: PERIOD_ID, item_key: "ar_aging_reconciled", label: "AR aging reconciled", required: true, source_capability: "FIN-210", satisfied: false, satisfied_reason: null, satisfied_by: null, satisfied_at: null, created_at: "2026-07-28T00:00:00.000Z" },
    ]);
    const items = await listFinancePeriodChecklistItems(client, PERIOD_ID);
    assert.equal(items.length, 1);
    assert.equal(items[0]?.itemKey, "ar_aging_reconciled");
  });
});

describe("resolveFinancePeriodForDate", () => {
  test("returns the resolved period for a covered date", async () => {
    const client = fakeClient({ data: [{ period_id: PERIOD_ID, period_code: "2026-01", status: "open", posting_eligible: true }], error: null });
    const resolution = await resolveFinancePeriodForDate(client, { tenantId: TENANT_ID, companyId: null, transactionDate: "2026-01-15" });
    assert.equal(resolution?.postingEligible, true);
  });

  test("returns null when no period covers the date", async () => {
    const client = fakeClient({ data: [], error: null });
    const resolution = await resolveFinancePeriodForDate(client, { tenantId: TENANT_ID, companyId: null, transactionDate: "1999-01-15" });
    assert.equal(resolution, null);
  });
});
