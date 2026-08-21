import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseTenantDashboard,
  parseTenantDashboardVersion,
  parseTenantDashboardWidget,
  CreateTenantDashboardDraftInputSchema,
  AddDashboardWidgetInputSchema,
  WidgetParameterOverridesSchema,
} from "./tenant-dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const DASHBOARD_ID = "423e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "523e4567-e89b-12d3-a456-426614174000";
const WIDGET_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseTenantDashboard", () => {
  test("maps snake_case fields", () => {
    const dashboard = parseTenantDashboard({
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
    });
    assert.equal(dashboard.name, "Executive Overview");
    assert.equal(dashboard.currentVersionId, null);
    assert.equal(dashboard.recordVersion, 1);
  });
});

describe("parseTenantDashboardVersion", () => {
  test("maps a published version", () => {
    const version = parseTenantDashboardVersion({
      id: VERSION_ID,
      dashboard_id: DASHBOARD_ID,
      version_number: 1,
      layout: { columns: 12 },
      status: "published",
      published_by_auth_user_id: ACTOR_ID,
      published_by: "tester",
      published_at: "2026-08-02T00:00:01.000Z",
      created_at: "2026-08-02T00:00:00.000Z",
    });
    assert.equal(version.status, "published");
    assert.deepEqual(version.layout, { columns: 12 });
  });

  test("maps a draft version with null publish fields", () => {
    const version = parseTenantDashboardVersion({
      id: VERSION_ID,
      dashboard_id: DASHBOARD_ID,
      version_number: 2,
      layout: {},
      status: "draft",
      published_by_auth_user_id: null,
      published_by: null,
      published_at: null,
      created_at: "2026-08-02T00:00:02.000Z",
    });
    assert.equal(version.publishedAt, null);
  });
});

describe("parseTenantDashboardWidget", () => {
  test("maps snake_case fields", () => {
    const widget = parseTenantDashboardWidget({
      id: WIDGET_ID,
      dashboard_version_id: VERSION_ID,
      report_type_code: "finance_billing_summary",
      title: "Billing Summary",
      position: { x: 0, y: 0 },
      parameter_overrides: { currency: "IDR" },
      display_order: 0,
      created_at: "2026-08-02T00:00:00.000Z",
    });
    assert.equal(widget.reportTypeCode, "finance_billing_summary");
    assert.equal(widget.displayOrder, 0);
    assert.deepEqual(widget.parameterOverrides, { currency: "IDR" });
  });
});

describe("CreateTenantDashboardDraftInputSchema", () => {
  test("defaults description to empty string", () => {
    const parsed = CreateTenantDashboardDraftInputSchema.parse({
      tenantId: TENANT_ID,
      name: "Executive Overview",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.description, "");
  });

  test("rejects an empty name", () => {
    assert.throws(() =>
      CreateTenantDashboardDraftInputSchema.parse({
        tenantId: TENANT_ID,
        name: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("AddDashboardWidgetInputSchema", () => {
  test("defaults position and parameterOverrides to empty objects", () => {
    const parsed = AddDashboardWidgetInputSchema.parse({
      dashboardVersionId: VERSION_ID,
      reportTypeCode: "finance_billing_summary",
      title: "Billing Summary",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.deepEqual(parsed.position, {});
    assert.deepEqual(parsed.parameterOverrides, {});
  });
});

describe("WidgetParameterOverridesSchema", () => {
  test("accepts a flat bag of strings/numbers/booleans/nulls", () => {
    const parsed = WidgetParameterOverridesSchema.parse({ currency: "IDR", limit: 10, includeArchived: false, ownerUserId: null });
    assert.equal(parsed.currency, "IDR");
  });

  test("rejects a nested object value -- parameters stay flat", () => {
    assert.throws(() => WidgetParameterOverridesSchema.parse({ nested: { a: 1 } }));
  });
});
