import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createSavedReportView,
  updateSavedReportView,
  deleteSavedReportView,
  SavedReportViewMutationError,
  type SavedReportViewMutationRpcClient,
} from "./saved-report-view.ts";

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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: SavedReportViewMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as SavedReportViewMutationRpcClient;
  return { client, calls };
}

describe("createSavedReportView", () => {
  test("calls create_saved_report_view with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_VIEW_ROW, error: null });
    const view = await createSavedReportView(client, {
      tenantId: TENANT_ID,
      reportTypeCode: "finance_billing_summary",
      name: "My Billing View",
      columns: ["invoiceNumber"],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "create_saved_report_view");
    assert.equal(calls[0]?.args.p_report_type_code, "finance_billing_summary");
    assert.equal(calls[0]?.args.p_sharing_scope, "private");
    assert.equal(view.name, "My Billing View");
  });

  test("classifies insufficient_authority (missing REP:Configure for a tenant-shared view)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks REP:Configure" } });
    await assert.rejects(
      () =>
        createSavedReportView(client, {
          tenantId: TENANT_ID,
          reportTypeCode: "finance_billing_summary",
          name: "x",
          columns: ["a"],
          sharingScope: "tenant",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof SavedReportViewMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () =>
        createSavedReportView(client, {
          tenantId: TENANT_ID,
          reportTypeCode: "finance_billing_summary",
          name: "x",
          columns: ["a"],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof SavedReportViewMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("updateSavedReportView", () => {
  test("calls update_saved_report_view with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_VIEW_ROW, name: "Renamed", record_version: 2 }, error: null });
    const view = await updateSavedReportView(client, {
      viewId: VIEW_ID,
      expectedVersion: 1,
      name: "Renamed",
      columns: ["invoiceNumber"],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "update_saved_report_view");
    assert.equal(calls[0]?.args.p_expected_version, 1);
    assert.equal(view.name, "Renamed");
  });

  test("classifies saved_report_view_not_found (a non-owner edit attempt)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "saved_report_view_not_found: not this actor's own view" } });
    await assert.rejects(
      () =>
        updateSavedReportView(client, {
          viewId: VIEW_ID,
          expectedVersion: 1,
          name: "x",
          columns: ["a"],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof SavedReportViewMutationError);
        assert.equal(err.code, "saved_report_view_not_found");
        return true;
      },
    );
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: saved view was changed by another request" } });
    await assert.rejects(
      () =>
        updateSavedReportView(client, {
          viewId: VIEW_ID,
          expectedVersion: 1,
          name: "x",
          columns: ["a"],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof SavedReportViewMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("deleteSavedReportView", () => {
  test("calls delete_saved_report_view with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: true, error: null });
    await deleteSavedReportView(client, { viewId: VIEW_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "delete_saved_report_view");
    assert.equal(calls[0]?.args.p_view_id, VIEW_ID);
  });

  test("classifies saved_report_view_not_found", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "saved_report_view_not_found: not this actor's own view" } });
    await assert.rejects(
      () => deleteSavedReportView(client, { viewId: VIEW_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof SavedReportViewMutationError);
        assert.equal(err.code, "saved_report_view_not_found");
        return true;
      },
    );
  });
});
