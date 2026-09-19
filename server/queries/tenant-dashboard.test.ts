import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listTenantDashboards,
  getTenantDashboardById,
  listTenantDashboardVersions,
  getTenantDashboardVersionById,
  listDashboardWidgets,
  TenantDashboardQueryError,
  type TenantDashboardQueryTableClient,
} from "./tenant-dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const DASHBOARD_ID = "423e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "523e4567-e89b-12d3-a456-426614174000";

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
  status: "draft",
  published_by_auth_user_id: null,
  published_by: null,
  published_at: null,
  created_at: "2026-08-02T00:00:00.000Z",
};

const VALID_WIDGET_ROW = {
  id: "623e4567-e89b-12d3-a456-426614174000",
  dashboard_version_id: VERSION_ID,
  report_type_code: "finance_billing_summary",
  title: "Billing Summary",
  position: {},
  parameter_overrides: {},
  display_order: 0,
  created_at: "2026-08-02T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: TenantDashboardQueryTableClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown> = {}) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as TenantDashboardQueryTableClient;
  return { client, calls };
}

describe("listTenantDashboards", () => {
  test("calls list_tenant_dashboards and maps dashboard rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_DASHBOARD_ROW], error: null });
    const dashboards = await listTenantDashboards(client, TENANT_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID });
    assert.equal(dashboards.length, 1);
    assert.equal(dashboards[0]?.name, "Executive Overview");
  });

  test("wraps a query error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listTenantDashboards(client, TENANT_ID),
      (err: unknown) => err instanceof TenantDashboardQueryError,
    );
  });
});

describe("getTenantDashboardById", () => {
  test("returns null (never an error) when not found", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const dashboard = await getTenantDashboardById(client, DASHBOARD_ID);
    assert.equal(dashboard, null);
  });

  test("parses a matched row", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_DASHBOARD_ROW], error: null });
    const dashboard = await getTenantDashboardById(client, DASHBOARD_ID);
    assert.deepEqual(calls[0]?.args, { p_dashboard_id: DASHBOARD_ID });
    assert.equal(dashboard?.id, DASHBOARD_ID);
  });
});

describe("listTenantDashboardVersions", () => {
  test("calls list_tenant_dashboard_versions and maps version-history rows, newest first", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_VERSION_ROW], error: null });
    const versions = await listTenantDashboardVersions(client, DASHBOARD_ID);
    assert.deepEqual(calls[0]?.args, { p_dashboard_id: DASHBOARD_ID });
    assert.equal(versions.length, 1);
    assert.equal(versions[0]?.versionNumber, 1);
  });
});

describe("getTenantDashboardVersionById", () => {
  test("returns null (never an error) when not found", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const version = await getTenantDashboardVersionById(client, VERSION_ID);
    assert.equal(version, null);
  });

  test("parses a matched row", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_VERSION_ROW], error: null });
    const version = await getTenantDashboardVersionById(client, VERSION_ID);
    assert.deepEqual(calls[0]?.args, { p_version_id: VERSION_ID });
    assert.equal(version?.id, VERSION_ID);
  });
});

describe("listDashboardWidgets", () => {
  test("calls list_dashboard_widgets and maps widget rows in display order", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_WIDGET_ROW], error: null });
    const widgets = await listDashboardWidgets(client, VERSION_ID);
    assert.deepEqual(calls[0]?.args, { p_dashboard_version_id: VERSION_ID });
    assert.equal(widgets.length, 1);
    assert.equal(widgets[0]?.reportTypeCode, "finance_billing_summary");
  });
});
