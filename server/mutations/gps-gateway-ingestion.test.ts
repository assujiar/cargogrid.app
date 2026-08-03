import { test } from "node:test";
import assert from "node:assert/strict";
import {
  resolveGpsDeviceForHandshake,
  ingestDirectDeviceTelemetryBatch,
  GpsGatewayIngestionMutationError,
  type GpsGatewayIngestionMutationRpcClient,
} from "./gps-gateway-ingestion.ts";

function fakeClient(response: { data: unknown; error: { message: string } | null }): GpsGatewayIngestionMutationRpcClient {
  return {
    rpc: async (_fn: string, _args: Record<string, unknown>) => response,
  } as unknown as GpsGatewayIngestionMutationRpcClient;
}

test("resolveGpsDeviceForHandshake parses an accepted result", async () => {
  const client = fakeClient({
    data: [{ accepted: true, device_id: "723e4567-e89b-12d3-a456-426614174003", tenant_id: "723e4567-e89b-12d3-a456-426614174002", rejection_reason: null }],
    error: null,
  });
  const result = await resolveGpsDeviceForHandshake(client, { rawApiKey: "cgk_abc", imei: "868712345600001" });
  assert.equal(result.accepted, true);
  assert.equal(result.deviceId, "723e4567-e89b-12d3-a456-426614174003");
});

test("resolveGpsDeviceForHandshake parses a rejected (never thrown) result", async () => {
  const client = fakeClient({
    data: [{ accepted: false, device_id: null, tenant_id: null, rejection_reason: "imei_not_registered" }],
    error: null,
  });
  const result = await resolveGpsDeviceForHandshake(client, { rawApiKey: "cgk_abc", imei: "999999999999999" });
  assert.equal(result.accepted, false);
  assert.equal(result.rejectionReason, "imei_not_registered");
});

test("resolveGpsDeviceForHandshake throws a classified error for a bad API key", async () => {
  const client = fakeClient({ data: null, error: { message: "api_key_not_found: presented key does not match any known key" } });
  await assert.rejects(
    () => resolveGpsDeviceForHandshake(client, { rawApiKey: "wrong", imei: "868712345600001" }),
    (err: unknown) => err instanceof GpsGatewayIngestionMutationError && err.code === "api_key_not_found",
  );
});

test("ingestDirectDeviceTelemetryBatch maps camelCase report fields to snake_case RPC args", async () => {
  let capturedArgs: Record<string, unknown> | undefined;
  const client = {
    rpc: async (_fn: string, args: Record<string, unknown>) => {
      capturedArgs = args;
      return { data: [{ device_id: "723e4567-e89b-12d3-a456-426614174003", tenant_id: "723e4567-e89b-12d3-a456-426614174002", accepted_count: 1, device_status: "active" }], error: null };
    },
  } as unknown as GpsGatewayIngestionMutationRpcClient;
  const result = await ingestDirectDeviceTelemetryBatch(client, {
    rawApiKey: "cgk_abc",
    deviceId: "723e4567-e89b-12d3-a456-426614174003",
    reports: [{ reportType: "location", eventAt: "2026-08-03T00:00:00Z", longitude: 106.8, latitude: -6.2 }],
  });
  assert.equal(result.acceptedCount, 1);
  const reports = capturedArgs?.p_reports as Record<string, unknown>[];
  assert.equal(reports[0]?.report_type, "location");
  assert.equal(reports[0]?.longitude, 106.8);
});

test("ingestDirectDeviceTelemetryBatch throws a classified error for a not-ingestible device", async () => {
  const client = fakeClient({ data: null, error: { message: "device_not_ingestible: device x is suspended and cannot accept telemetry" } });
  await assert.rejects(
    () =>
      ingestDirectDeviceTelemetryBatch(client, {
        rawApiKey: "cgk_abc",
        deviceId: "723e4567-e89b-12d3-a456-426614174003",
        reports: [{ reportType: "heartbeat", eventAt: "2026-08-03T00:00:00Z" }],
      }),
    (err: unknown) => err instanceof GpsGatewayIngestionMutationError && err.code === "device_not_ingestible",
  );
});
