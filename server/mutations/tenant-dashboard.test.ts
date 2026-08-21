import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createTenantDashboardDraft,
  addDashboardWidget,
  removeDashboardWidget,
  publishTenantDashboardVersion,
  rollbackTenantDashboard,
  TenantDashboardMutationError,
  type TenantDashboardMutationRpcClient,
} from "./tenant-dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const DASHBOARD_ID = "423e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "523e4567-e89b-12d3-a456-426614174000";
const WIDGET_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_DASHBOARD_ROW = {
  id: DASHBOARD_ID,
  tenant_id: TENANT_ID,
  name: "Executive Overview",
  description: "",
  status: "draft",
  current_version_id: null,
  created_by_auth_user_id: ACTOR_ID,
  created_by: "tester",
  record_version: 1,
  created_at: "2026-08-02T00:00:00.000Z",
  updated_at: "2026-08-02T00:00:00.000Z",
};

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  dashboard_id: DASHBOARD_ID,
  version_number: 1,
  layout: {},
  status: "published",
  published_by_auth_user_id: ACTOR_ID,
  published_by: "tester",
  published_at: "2026-08-02T00:00:01.000Z",
  created_at: "2026-08-02T00:00:00.000Z",
};

const VALID_WIDGET_ROW = {
  id: WIDGET_ID,
  dashboard_version_id: VERSION_ID,
  report_type_code: "finance_billing_summary",
  title: "Billing Summary",
  position: {},
  parameter_overrides: {},
  display_order: 0,
  created_at: "2026-08-02T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: TenantDashboardMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TenantDashboardMutationRpcClient;
  return { client, calls };
}

describe("createTenantDashboardDraft", () => {
  test("calls create_tenant_dashboard_draft with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_DASHBOARD_ROW, error: null });
    const dashboard = await createTenantDashboardDraft(client, {
      tenantId: TENANT_ID,
      name: "Executive Overview",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "create_tenant_dashboard_draft");
    assert.equal(calls[0]?.args.p_name, "Executive Overview");
    assert.equal(dashboard.status, "draft");
  });

  test("classifies insufficient_authority (missing REP:Configure)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks REP:Configure" } });
    await assert.rejects(
      () => createTenantDashboardDraft(client, { tenantId: TENANT_ID, name: "Executive Overview", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof TenantDashboardMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () => createTenantDashboardDraft(client, { tenantId: TENANT_ID, name: "Executive Overview", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof TenantDashboardMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});

describe("addDashboardWidget", () => {
  test("calls add_dashboard_widget and returns the new widget", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_WIDGET_ROW, error: null });
    const widget = await addDashboardWidget(client, {
      dashboardVersionId: VERSION_ID,
      reportTypeCode: "finance_billing_summary",
      title: "Billing Summary",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "add_dashboard_widget");
    assert.equal(calls[0]?.args.p_report_type_code, "finance_billing_summary");
    assert.equal(widget.title, "Billing Summary");
  });

  test("classifies report_type_retired", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "report_type_retired: some_code is retired and cannot be added to a dashboard" } });
    await assert.rejects(
      () =>
        addDashboardWidget(client, {
          dashboardVersionId: VERSION_ID,
          reportTypeCode: "some_code",
          title: "Widget",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof TenantDashboardMutationError);
        assert.equal(err.code, "report_type_retired");
        return true;
      },
    );
  });
});

describe("removeDashboardWidget", () => {
  test("calls remove_dashboard_widget with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: null });
    await removeDashboardWidget(client, { widgetId: WIDGET_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "remove_dashboard_widget");
    assert.equal(calls[0]?.args.p_widget_id, WIDGET_ID);
  });

  test("classifies dashboard_version_not_editable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "dashboard_version_not_editable: version is published" } });
    await assert.rejects(
      () => removeDashboardWidget(client, { widgetId: WIDGET_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof TenantDashboardMutationError);
        assert.equal(err.code, "dashboard_version_not_editable");
        return true;
      },
    );
  });
});

describe("publishTenantDashboardVersion", () => {
  test("calls publish_tenant_dashboard_version and returns the newly published version", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_VERSION_ROW, error: null });
    const version = await publishTenantDashboardVersion(client, { dashboardId: DASHBOARD_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "publish_tenant_dashboard_version");
    assert.equal(calls[0]?.args.p_dashboard_id, DASHBOARD_ID);
    assert.equal(version.status, "published");
  });

  test("classifies dashboard_empty_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "dashboard_empty_version: a version with zero widgets cannot be published" } });
    await assert.rejects(
      () => publishTenantDashboardVersion(client, { dashboardId: DASHBOARD_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof TenantDashboardMutationError);
        assert.equal(err.code, "dashboard_empty_version");
        return true;
      },
    );
  });
});

describe("rollbackTenantDashboard", () => {
  test("calls rollback_tenant_dashboard with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_DASHBOARD_ROW, current_version_id: VERSION_ID }, error: null });
    const dashboard = await rollbackTenantDashboard(client, { dashboardId: DASHBOARD_ID, targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "rollback_tenant_dashboard");
    assert.equal(calls[0]?.args.p_target_version_id, VERSION_ID);
    assert.equal(dashboard.currentVersionId, VERSION_ID);
  });

  test("classifies dashboard_target_version_invalid", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "dashboard_target_version_invalid: version is not published" } });
    await assert.rejects(
      () => rollbackTenantDashboard(client, { dashboardId: DASHBOARD_ID, targetVersionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof TenantDashboardMutationError);
        assert.equal(err.code, "dashboard_target_version_invalid");
        return true;
      },
    );
  });
});
