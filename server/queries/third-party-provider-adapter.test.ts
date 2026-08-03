import { test } from "node:test";
import assert from "node:assert/strict";
import {
  getThirdPartyProviderConnection,
  listThirdPartyTelemetryReports,
  ThirdPartyProviderAdapterQueryError,
  type ThirdPartyProviderAdapterQueryClient,
} from "./third-party-provider-adapter.ts";

const CONN_ID = "723e4567-e89b-12d3-a456-426614174001";
const TENANT_ID = "723e4567-e89b-12d3-a456-426614174002";
const VEHICLE_ID = "723e4567-e89b-12d3-a456-426614174003";

function fakeClient(overrides: {
  fromResponse?: { data: unknown; error: { message: string } | null };
  rpcResponse?: { data: unknown; error: { message: string } | null };
}): ThirdPartyProviderAdapterQueryClient {
  return {
    from: (_table: string) => ({
      select: (_cols: string) => ({
        eq: (_c1: string, _v1: unknown) => ({
          eq: (_c2: string, _v2: unknown) => ({
            maybeSingle: async () => overrides.fromResponse,
          }),
        }),
      }),
    }),
    rpc: async (_fn: string, _args: Record<string, unknown>) => overrides.rpcResponse,
  } as unknown as ThirdPartyProviderAdapterQueryClient;
}

test("getThirdPartyProviderConnection returns null when no connection exists", async () => {
  const client = fakeClient({ fromResponse: { data: null, error: null } });
  const result = await getThirdPartyProviderConnection(client, TENANT_ID, "acmegps");
  assert.equal(result, null);
});

test("getThirdPartyProviderConnection parses a real row", async () => {
  const client = fakeClient({
    fromResponse: {
      data: {
        id: CONN_ID,
        tenant_id: TENANT_ID,
        provider_code: "acmegps",
        integration_mode: "webhook",
        poll_cursor: null,
        status: "active",
        consecutive_failure_count: 0,
        last_successful_ingest_at: null,
        created_at: "2026-08-03T00:00:00Z",
        updated_at: "2026-08-03T00:00:00Z",
      },
      error: null,
    },
  });
  const result = await getThirdPartyProviderConnection(client, TENANT_ID, "acmegps");
  assert.equal(result?.providerCode, "acmegps");
});

test("getThirdPartyProviderConnection throws on an RPC/query error", async () => {
  const client = fakeClient({ fromResponse: { data: null, error: { message: "boom" } } });
  await assert.rejects(() => getThirdPartyProviderConnection(client, TENANT_ID, "acmegps"), ThirdPartyProviderAdapterQueryError);
});

test("listThirdPartyTelemetryReports maps every row through the parser", async () => {
  const client = fakeClient({
    rpcResponse: {
      data: [
        {
          id: CONN_ID,
          tenant_id: TENANT_ID,
          connection_id: CONN_ID,
          vehicle_master_id: VEHICLE_ID,
          provider_event_id: "evt-001",
          report_type: "location",
          event_at: "2026-08-03T00:00:00Z",
          received_at: "2026-08-03T00:00:01Z",
          location_geojson: { type: "Point", coordinates: [106.8, -6.2] },
          speed_kmh: null,
          heading_degrees: null,
          raw_fields: {},
          created_at: "2026-08-03T00:00:01Z",
        },
      ],
      error: null,
    },
  });
  const result = await listThirdPartyTelemetryReports(client, CONN_ID);
  assert.equal(result.length, 1);
  assert.equal(result[0]?.longitude, 106.8);
});

test("listThirdPartyTelemetryReports returns an empty array for null data", async () => {
  const client = fakeClient({ rpcResponse: { data: null, error: null } });
  const result = await listThirdPartyTelemetryReports(client, CONN_ID);
  assert.deepEqual(result, []);
});
