import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseSavedReportView,
  CreateSavedReportViewInputSchema,
  UpdateSavedReportViewInputSchema,
  SavedReportViewFiltersSchema,
} from "./saved-report-view.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const VIEW_ID = "423e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseSavedReportView", () => {
  test("maps snake_case fields", () => {
    const view = parseSavedReportView({
      id: VIEW_ID,
      tenant_id: TENANT_ID,
      report_type_code: "finance_billing_summary",
      report_type_version_id: VERSION_ID,
      owner_auth_user_id: ACTOR_ID,
      owner_label: "tester",
      name: "My Billing View",
      description: null,
      sharing_scope: "private",
      columns: ["invoiceNumber", "amount"],
      filters: { currency: "IDR" },
      sort: { field: "dueDate", direction: "asc" },
      grouping: {},
      record_version: 1,
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(view.reportTypeCode, "finance_billing_summary");
    assert.equal(view.sharingScope, "private");
    assert.deepEqual(view.columns, ["invoiceNumber", "amount"]);
  });

  test("defaults nullable jsonb columns to empty structures", () => {
    const view = parseSavedReportView({
      id: VIEW_ID,
      tenant_id: TENANT_ID,
      report_type_code: "finance_billing_summary",
      report_type_version_id: null,
      owner_auth_user_id: ACTOR_ID,
      owner_label: null,
      name: "x",
      description: null,
      sharing_scope: "tenant",
      columns: null,
      filters: null,
      sort: null,
      grouping: null,
      record_version: 1,
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    });
    assert.deepEqual(view.columns, []);
    assert.deepEqual(view.filters, {});
    assert.equal(view.reportTypeVersionId, null);
  });
});

describe("CreateSavedReportViewInputSchema", () => {
  test("defaults sharingScope to private and description to null", () => {
    const parsed = CreateSavedReportViewInputSchema.parse({
      tenantId: TENANT_ID,
      reportTypeCode: "finance_billing_summary",
      name: "My View",
      columns: ["invoiceNumber"],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.sharingScope, "private");
    assert.equal(parsed.description, null);
  });

  test("rejects an empty columns array", () => {
    assert.throws(() =>
      CreateSavedReportViewInputSchema.parse({
        tenantId: TENANT_ID,
        reportTypeCode: "finance_billing_summary",
        name: "My View",
        columns: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("UpdateSavedReportViewInputSchema", () => {
  test("requires a positive expectedVersion", () => {
    assert.throws(() =>
      UpdateSavedReportViewInputSchema.parse({
        viewId: VIEW_ID,
        expectedVersion: 0,
        name: "x",
        columns: ["a"],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("SavedReportViewFiltersSchema", () => {
  test("accepts a flat bag of strings/numbers/booleans/nulls", () => {
    const parsed = SavedReportViewFiltersSchema.parse({ ownerUserId: "u-1", limit: 10, includeArchived: false, periodEnd: null });
    assert.equal(parsed.ownerUserId, "u-1");
  });

  test("rejects a nested object value -- filters stay flat", () => {
    assert.throws(() => SavedReportViewFiltersSchema.parse({ nested: { a: 1 } }));
  });
});
