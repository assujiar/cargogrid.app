import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getSavedReportViewById, listSavedReportViews, SavedReportViewQueryError, type SavedReportViewQueryClient } from "./saved-report-view.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const VIEW_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_VIEW_ROW = {
  id: VIEW_ID,
  tenant_id: TENANT_ID,
  report_type_code: "finance_billing_summary",
  report_type_version_id: null,
  owner_auth_user_id: ACTOR_ID,
  owner_label: "tester",
  name: "My Billing View",
  description: null,
  sharing_scope: "private",
  columns: ["invoiceNumber"],
  filters: {},
  sort: {},
  grouping: {},
  record_version: 1,
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
};

function fakeClient(tableResponse: { data: unknown; error: { message: string } | null }, rpcResponse?: { data: unknown; error: { message: string } | null }): {
  client: SavedReportViewQueryClient;
  rpcCalls: { fn: string; args: Record<string, unknown> }[];
} {
  const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
  function chainNode(): unknown {
    return {
      select: () => chainNode(),
      eq: () => chainNode(),
      maybeSingle: () => Promise.resolve(tableResponse),
      then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) => Promise.resolve(tableResponse).then(resolve, reject),
    };
  }
  const client = {
    from: () => chainNode(),
    async rpc(fn: string, args: Record<string, unknown>) {
      rpcCalls.push({ fn, args });
      return rpcResponse ?? { data: [], error: null };
    },
  } as unknown as SavedReportViewQueryClient;
  return { client, rpcCalls };
}

describe("getSavedReportViewById", () => {
  test("returns null (never an error) when not found", async () => {
    const { client } = fakeClient({ data: null, error: null });
    const view = await getSavedReportViewById(client, VIEW_ID);
    assert.equal(view, null);
  });

  test("parses a matched row", async () => {
    const { client } = fakeClient({ data: VALID_VIEW_ROW, error: null });
    const view = await getSavedReportViewById(client, VIEW_ID);
    assert.equal(view?.name, "My Billing View");
  });

  test("wraps a query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getSavedReportViewById(client, VIEW_ID),
      (err: unknown) => err instanceof SavedReportViewQueryError,
    );
  });
});

describe("listSavedReportViews", () => {
  test("calls list_saved_report_views with the exact snake_case params", async () => {
    const { client, rpcCalls } = fakeClient({ data: null, error: null }, { data: [VALID_VIEW_ROW], error: null });
    const views = await listSavedReportViews(client, TENANT_ID, ACTOR_ID, { reportTypeCode: "finance_billing_summary", limit: 10 });
    assert.equal(rpcCalls[0]?.fn, "list_saved_report_views");
    assert.equal(rpcCalls[0]?.args.p_report_type_code, "finance_billing_summary");
    assert.equal(rpcCalls[0]?.args.p_limit, 10);
    assert.equal(views.length, 1);
    assert.equal(views[0]?.reportTypeCode, "finance_billing_summary");
  });

  test("defaults reportTypeCode/cursor to null and limit to 25", async () => {
    const { client, rpcCalls } = fakeClient({ data: null, error: null }, { data: [], error: null });
    await listSavedReportViews(client, TENANT_ID, ACTOR_ID);
    assert.equal(rpcCalls[0]?.args.p_report_type_code, null);
    assert.equal(rpcCalls[0]?.args.p_limit, 25);
    assert.equal(rpcCalls[0]?.args.p_cursor, null);
  });

  test("wraps a query error", async () => {
    const { client } = fakeClient({ data: null, error: null }, { data: null, error: { message: "insufficient_authority: no membership" } });
    await assert.rejects(
      () => listSavedReportViews(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => err instanceof SavedReportViewQueryError,
    );
  });
});
