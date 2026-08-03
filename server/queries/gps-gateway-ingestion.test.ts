import { test } from "node:test";
import assert from "node:assert/strict";
import { listDirectDeviceTelemetryReports, GpsGatewayIngestionQueryError, type GpsGatewayIngestionQueryClient } from "./gps-gateway-ingestion.ts";

function fakeClient(response: { data: unknown; error: { message: string } | null }): GpsGatewayIngestionQueryClient {
  return {
    rpc: async (_fn: string, _args: Record<string, unknown>) => response,
  } as unknown as GpsGatewayIngestionQueryClient;
}

test("listDirectDeviceTelemetryReports maps every row through the parser", async () => {
  const client = fakeClient({
    data: [
      {
        id: "723e4567-e89b-12d3-a456-426614174001",
        tenant_id: "723e4567-e89b-12d3-a456-426614174002",
        device_id: "723e4567-e89b-12d3-a456-426614174003",
        report_type: "location",
        event_at: "2026-08-03T00:00:00Z",
        received_at: "2026-08-03T00:00:01Z",
        location_geojson: { type: "Point", coordinates: [106.8, -6.2] },
        altitude_meters: null,
        heading_degrees: null,
        speed_kmh: null,
        satellite_count: null,
        raw_codec_id: "8E",
        io_elements: {},
        created_at: "2026-08-03T00:00:01Z",
      },
    ],
    error: null,
  });
  const result = await listDirectDeviceTelemetryReports(client, "723e4567-e89b-12d3-a456-426614174003");
  assert.equal(result.length, 1);
  assert.equal(result[0]?.longitude, 106.8);
});

test("listDirectDeviceTelemetryReports returns an empty array for null data", async () => {
  const client = fakeClient({ data: null, error: null });
  const result = await listDirectDeviceTelemetryReports(client, "723e4567-e89b-12d3-a456-426614174003");
  assert.deepEqual(result, []);
});

test("listDirectDeviceTelemetryReports throws GpsGatewayIngestionQueryError on an RPC error", async () => {
  const client = fakeClient({ data: null, error: { message: "boom" } });
  await assert.rejects(() => listDirectDeviceTelemetryReports(client, "723e4567-e89b-12d3-a456-426614174003"), GpsGatewayIngestionQueryError);
});
