import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  generateFinanceFiscalCalendar,
  acknowledgeFinancePeriodChecklistItem,
  softCloseFinancePeriod,
  closeFinancePeriod,
  reopenFinancePeriod,
  FiscalPeriodMutationError,
  type FiscalPeriodMutationRpcClient,
} from "./fiscal-period.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const PERIOD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

const CALENDAR_ROW = {
  id: "523e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  company_id: null,
  code: "FY2026",
  name: "Fiscal Year 2026",
  created_by: "finance-manager",
  created_at: "2026-07-28T00:00:00.000Z",
};

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

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): FiscalPeriodMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as FiscalPeriodMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("generateFinanceFiscalCalendar", () => {
  test("calls generate_finance_fiscal_calendar with the exact snake_case params", async () => {
    const client = fakeClient({ data: CALENDAR_ROW, error: null });
    await generateFinanceFiscalCalendar(client, {
      tenantId: TENANT_ID,
      code: "FY2026",
      name: "Fiscal Year 2026",
      startDate: "2026-01-01",
      periodCount: 12,
      actorAuthUserId: ACTOR_ID,
      createdBy: "finance-manager",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_company_id: null,
      p_code: "FY2026",
      p_name: "Fiscal Year 2026",
      p_start_date: "2026-01-01",
      p_period_count: 12,
      p_actor_auth_user_id: ACTOR_ID,
      p_created_by: "finance-manager",
    });
  });

  test("wraps a finance_period_overlap error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_period_overlap: the period starting 2026-01-01 would overlap an existing period in this tenant/company scope" } });
    await assert.rejects(
      () => generateFinanceFiscalCalendar(client, { tenantId: TENANT_ID, code: "FY2026B", name: "Overlap", startDate: "2026-01-01", periodCount: 1, actorAuthUserId: ACTOR_ID, createdBy: "finance-manager" }),
      (err: unknown) => {
        assert.ok(err instanceof FiscalPeriodMutationError);
        assert.equal(err.code, "finance_period_overlap");
        return true;
      },
    );
  });
});

describe("acknowledgeFinancePeriodChecklistItem", () => {
  test("calls acknowledge_finance_period_checklist_item with the exact snake_case params", async () => {
    const client = fakeClient({
      data: { id: "623e4567-e89b-12d3-a456-426614174000", period_id: PERIOD_ID, item_key: "ar_aging_reconciled", label: "AR aging reconciled", required: true, source_capability: "FIN-210", satisfied: true, satisfied_reason: "reconciled manually", satisfied_by: "finance-manager", satisfied_at: "2026-07-28T00:00:00.000Z", created_at: "2026-07-28T00:00:00.000Z" },
      error: null,
    });
    const item = await acknowledgeFinancePeriodChecklistItem(client, { periodId: PERIOD_ID, itemKey: "ar_aging_reconciled", satisfied: true, reason: "reconciled manually", actorAuthUserId: ACTOR_ID, actorLabel: "finance-manager" });
    assert.equal(item.satisfied, true);
  });

  test("wraps a finance_period_closed error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_period_closed: period is closed -- checklist items on a closed period cannot be changed" } });
    await assert.rejects(
      () => acknowledgeFinancePeriodChecklistItem(client, { periodId: PERIOD_ID, itemKey: "ar_aging_reconciled", satisfied: true, actorAuthUserId: ACTOR_ID, actorLabel: "finance-manager" }),
      (err: unknown) => {
        assert.ok(err instanceof FiscalPeriodMutationError);
        assert.equal(err.code, "finance_period_closed");
        return true;
      },
    );
  });
});

describe("softCloseFinancePeriod", () => {
  test("calls soft_close_finance_period and returns the soft-closed row", async () => {
    const client = fakeClient({ data: { ...PERIOD_ROW, status: "soft_closed" }, error: null });
    const period = await softCloseFinancePeriod(client, { periodId: PERIOD_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "finance-manager" });
    assert.equal(period.status, "soft_closed");
  });
});

describe("closeFinancePeriod", () => {
  test("wraps a finance_period_checklist_incomplete error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_period_checklist_incomplete: period has 1 unsatisfied required close-checklist item(s)" } });
    await assert.rejects(
      () => closeFinancePeriod(client, { periodId: PERIOD_ID, expectedVersion: 2, actorAuthUserId: ACTOR_ID, actorLabel: "finance-approver" }),
      (err: unknown) => {
        assert.ok(err instanceof FiscalPeriodMutationError);
        assert.equal(err.code, "finance_period_checklist_incomplete");
        return true;
      },
    );
  });
});

describe("reopenFinancePeriod", () => {
  test("calls reopen_finance_period with the exact snake_case params including the mandatory reason", async () => {
    const client = fakeClient({ data: { ...PERIOD_ROW, status: "open" }, error: null });
    await reopenFinancePeriod(client, { periodId: PERIOD_ID, expectedVersion: 3, reason: "correcting a posting error", actorAuthUserId: ACTOR_ID, actorLabel: "finance-approver" });

    assert.deepEqual(client.calls[0]?.args, {
      p_period_id: PERIOD_ID,
      p_expected_version: 3,
      p_reason: "correcting a posting error",
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "finance-approver",
    });
  });

  test("wraps a finance_period_reopen_reason_required error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_period_reopen_reason_required: a non-empty reason is required" } });
    await assert.rejects(
      () => reopenFinancePeriod(client, { periodId: PERIOD_ID, expectedVersion: 3, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "finance-approver" }),
      (err: unknown) => {
        assert.ok(err instanceof FiscalPeriodMutationError);
        assert.equal(err.code, "finance_period_reopen_reason_required");
        return true;
      },
    );
  });
});
