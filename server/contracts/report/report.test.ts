import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseReportType,
  parseReportRun,
  RecordReportRunInputSchema,
  EnqueueReportExportInputSchema,
  ReportParametersSchema,
} from "./report.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "423e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseReportType", () => {
  test("maps snake_case fields", () => {
    const type = parseReportType({
      code: "lead_aging",
      name: "Lead Aging",
      description: "Open lead count bucketed by age.",
      source_function: "get_dashboard_lead_aging",
      version: 1,
      status: "active",
      registered_by: "system",
      created_at: "2026-07-26T00:00:00.000Z",
    });
    assert.equal(type.sourceFunction, "get_dashboard_lead_aging");
    assert.equal(type.status, "active");
  });
});

describe("parseReportRun", () => {
  test("maps a queued export run", () => {
    const run = parseReportRun({
      id: RUN_ID,
      tenant_id: TENANT_ID,
      report_type_code: "pipeline_summary",
      run_type: "export",
      status: "queued",
      parameters: { orgUnitId: null },
      row_count: null,
      masked_columns: [],
      job_id: JOB_ID,
      file_id: null,
      error_reason: null,
      requested_by_auth_user_id: ACTOR_ID,
      created_by: "tester",
      requested_at: "2026-07-26T00:00:00.000Z",
      completed_at: null,
    });
    assert.equal(run.runType, "export");
    assert.equal(run.status, "queued");
    assert.equal(run.jobId, JOB_ID);
    assert.equal(run.rowCount, null);
  });

  test("maps a completed preview run with masked columns", () => {
    const run = parseReportRun({
      id: RUN_ID,
      tenant_id: TENANT_ID,
      report_type_code: "margin_summary",
      run_type: "preview",
      status: "completed",
      parameters: {},
      row_count: 2,
      masked_columns: ["avgMarginPct", "totalMarginAmount"],
      job_id: null,
      file_id: null,
      error_reason: null,
      requested_by_auth_user_id: ACTOR_ID,
      created_by: "tester",
      requested_at: "2026-07-26T00:00:00.000Z",
      completed_at: "2026-07-26T00:00:01.000Z",
    });
    assert.deepEqual(run.maskedColumns, ["avgMarginPct", "totalMarginAmount"]);
    assert.equal(run.rowCount, 2);
  });
});

describe("ReportParametersSchema", () => {
  test("accepts an empty parameter bag", () => {
    const parsed = ReportParametersSchema.parse({});
    assert.deepEqual(parsed, {});
  });

  test("accepts a flat bag of strings/numbers/booleans/nulls -- the shape a report's own declared parameter_schema uses", () => {
    const parsed = ReportParametersSchema.parse({ currency: "IDR", limit: 10, includeArchived: false, ownerUserId: null });
    assert.equal(parsed.currency, "IDR");
    assert.equal(parsed.limit, 10);
    assert.equal(parsed.includeArchived, false);
    assert.equal(parsed.ownerUserId, null);
  });

  test("rejects a nested object value -- parameters stay flat", () => {
    assert.throws(() => ReportParametersSchema.parse({ nested: { a: 1 } }));
  });
});

describe("RecordReportRunInputSchema", () => {
  test("defaults maskedColumns to an empty array", () => {
    const parsed = RecordReportRunInputSchema.parse({
      tenantId: TENANT_ID,
      reportTypeCode: "lead_aging",
      rowCount: 4,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.deepEqual(parsed.maskedColumns, []);
  });

  test("rejects a negative rowCount", () => {
    assert.throws(() =>
      RecordReportRunInputSchema.parse({
        tenantId: TENANT_ID,
        reportTypeCode: "lead_aging",
        rowCount: -1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("EnqueueReportExportInputSchema", () => {
  test("requires a non-empty reportTypeCode", () => {
    assert.throws(() =>
      EnqueueReportExportInputSchema.parse({
        tenantId: TENANT_ID,
        reportTypeCode: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});
