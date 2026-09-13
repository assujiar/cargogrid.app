import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listActiveReportTypes,
  getReportTypeByCode,
  listReportRuns,
  listReportRunsForType,
  listReportTypeVersions,
  ReportQueryError,
  type ReportQueryTableClient,
} from "./report.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

const VALID_TYPE_ROW = {
  code: "lead_aging",
  name: "Lead Aging",
  description: "Open lead count bucketed by age.",
  source_function: "get_dashboard_lead_aging",
  version: 1,
  status: "active",
  registered_by: "system",
  created_at: "2026-07-26T00:00:00.000Z",
};

const VALID_RUN_ROW = {
  id: "423e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  report_type_code: "lead_aging",
  run_type: "preview",
  status: "completed",
  parameters: {},
  row_count: 4,
  masked_columns: [],
  job_id: null,
  file_id: null,
  error_reason: null,
  requested_by_auth_user_id: ACTOR_ID,
  created_by: "tester",
  requested_at: "2026-07-26T00:00:00.000Z",
  completed_at: "2026-07-26T00:00:01.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ReportQueryTableClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown> = {}) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ReportQueryTableClient;
  return { client, calls };
}

describe("listActiveReportTypes", () => {
  test("calls list_active_report_types and maps rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_TYPE_ROW], error: null });
    const types = await listActiveReportTypes(client);
    assert.equal(calls[0]?.fn, "list_active_report_types");
    assert.equal(types.length, 1);
    assert.equal(types[0]?.code, "lead_aging");
  });

  test("wraps a query error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listActiveReportTypes(client),
      (err: unknown) => err instanceof ReportQueryError,
    );
  });
});

describe("getReportTypeByCode", () => {
  test("returns null (never an error) when not found", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const type = await getReportTypeByCode(client, "unknown_code");
    assert.equal(type, null);
  });

  test("parses a matched row", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_TYPE_ROW], error: null });
    const type = await getReportTypeByCode(client, "lead_aging");
    assert.deepEqual(calls[0]?.args, { p_code: "lead_aging" });
    assert.equal(type?.sourceFunction, "get_dashboard_lead_aging");
  });
});

describe("listReportRuns", () => {
  test("calls list_report_runs with a null p_report_type_code and maps run rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_RUN_ROW], error: null });
    const runs = await listReportRuns(client, TENANT_ID);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_report_type_code: null, p_limit: 50 });
    assert.equal(runs.length, 1);
    assert.equal(runs[0]?.rowCount, 4);
  });
});

describe("listReportRunsForType", () => {
  test("calls list_report_runs with the report type code and maps run rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_RUN_ROW], error: null });
    const runs = await listReportRunsForType(client, TENANT_ID, "lead_aging");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_report_type_code: "lead_aging", p_limit: 50 });
    assert.equal(runs.length, 1);
    assert.equal(runs[0]?.reportTypeCode, "lead_aging");
  });
});

describe("listReportTypeVersions", () => {
  test("calls list_report_type_versions and maps version-history rows, newest first", async () => {
    const versionRow = {
      id: "623e4567-e89b-12d3-a456-426614174000",
      report_type_code: "lead_aging",
      version_number: 1,
      source_function: "get_dashboard_lead_aging",
      parameter_schema: {},
      description: "Open lead count bucketed by age.",
      published_by_auth_user_id: null,
      published_by: "system",
      published_at: "2026-07-26T00:00:00.000Z",
    };
    const { client, calls } = fakeRpcClient({ data: [versionRow], error: null });
    const versions = await listReportTypeVersions(client, "lead_aging");
    assert.deepEqual(calls[0]?.args, { p_report_type_code: "lead_aging" });
    assert.equal(versions.length, 1);
    assert.equal(versions[0]?.versionNumber, 1);
  });
});
