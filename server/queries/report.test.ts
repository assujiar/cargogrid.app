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

/** A chain node is simultaneously "chainable" (select/eq/order/limit each return another node) and "awaitable" (its own `then` resolves to `response`), so it works regardless of which query function's exact chain shape (with or without a trailing .limit()/.maybeSingle()) exercises it -- mirrors server/queries/pipeline.test.ts's own simpler fixed-shape fake, generalized since this file's four query functions each end their chain differently. */
function fakeTableClient(response: { data: unknown; error: { message: string } | null }): ReportQueryTableClient {
  function chainNode(): unknown {
    return {
      select: () => chainNode(),
      eq: () => chainNode(),
      order: () => chainNode(),
      limit: () => Promise.resolve(response),
      maybeSingle: () => {
        const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
        return Promise.resolve({ data: row, error: response.error });
      },
      then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) => Promise.resolve(response).then(resolve, reject),
    };
  }
  return { from: () => chainNode() } as unknown as ReportQueryTableClient;
}

describe("listActiveReportTypes", () => {
  test("maps rows", async () => {
    const client = fakeTableClient({ data: [VALID_TYPE_ROW], error: null });
    const types = await listActiveReportTypes(client);
    assert.equal(types.length, 1);
    assert.equal(types[0]?.code, "lead_aging");
  });

  test("wraps a query error", async () => {
    const client = fakeTableClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listActiveReportTypes(client),
      (err: unknown) => err instanceof ReportQueryError,
    );
  });
});

describe("getReportTypeByCode", () => {
  test("returns null (never an error) when not found", async () => {
    const client = fakeTableClient({ data: null, error: null });
    const type = await getReportTypeByCode(client, "unknown_code");
    assert.equal(type, null);
  });

  test("parses a matched row", async () => {
    const client = fakeTableClient({ data: VALID_TYPE_ROW, error: null });
    const type = await getReportTypeByCode(client, "lead_aging");
    assert.equal(type?.sourceFunction, "get_dashboard_lead_aging");
  });
});

describe("listReportRuns", () => {
  test("maps run rows", async () => {
    const client = fakeTableClient({ data: [VALID_RUN_ROW], error: null });
    const runs = await listReportRuns(client, TENANT_ID);
    assert.equal(runs.length, 1);
    assert.equal(runs[0]?.rowCount, 4);
  });
});

describe("listReportRunsForType", () => {
  test("maps run rows filtered to one report type", async () => {
    const client = fakeTableClient({ data: [VALID_RUN_ROW], error: null });
    const runs = await listReportRunsForType(client, TENANT_ID, "lead_aging");
    assert.equal(runs.length, 1);
    assert.equal(runs[0]?.reportTypeCode, "lead_aging");
  });
});

describe("listReportTypeVersions", () => {
  test("maps version-history rows, newest first", async () => {
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
    const client = fakeTableClient({ data: [versionRow], error: null });
    const versions = await listReportTypeVersions(client, "lead_aging");
    assert.equal(versions.length, 1);
    assert.equal(versions[0]?.versionNumber, 1);
  });
});
