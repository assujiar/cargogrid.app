/**
 * Entrypoint: wires the TCP listener, the health/readiness/metrics HTTP server, and
 * the durable-buffer flush loop together (226_GPS_TELEMATICS_INTEGRATION_PROMPT.md
 * §14B). Configuration is env-var only -- no config file, matching this repository's
 * own `scripts/env/` convention of failing loudly on a missing required value rather
 * than silently defaulting a secret.
 */

import { GpsGatewayServer } from "./server.ts";
import { HealthServer } from "./health.ts";
import { DurableTelemetryBuffer } from "./buffer.ts";
import { GpsGatewayIngestClient } from "./ingestClient.ts";
import { log } from "./logger.ts";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value || value.length === 0) {
    throw new Error(`missing_required_env: ${name} is required`);
  }
  return value;
}

async function main(): Promise<void> {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const rawApiKey = requireEnv("GPS_GATEWAY_API_KEY");
  const gatewayInstanceLabel = process.env.GPS_GATEWAY_INSTANCE_LABEL ?? "gps-gateway";
  const tcpPort = Number(process.env.GPS_GATEWAY_TCP_PORT ?? 6060);
  const tcpHost = process.env.GPS_GATEWAY_TCP_HOST ?? "0.0.0.0";
  const healthPort = Number(process.env.GPS_GATEWAY_HEALTH_PORT ?? 8080);
  const healthHost = process.env.GPS_GATEWAY_HEALTH_HOST ?? "0.0.0.0";
  const bufferFilePath = process.env.GPS_GATEWAY_BUFFER_FILE_PATH ?? "./data/telemetry-buffer.jsonl";
  const flushIntervalMs = Number(process.env.GPS_GATEWAY_FLUSH_INTERVAL_MS ?? 30_000);
  // ATW-246 finding 6 (TCP socket exhaustion): overridable, but defaulted sanely inside
  // GpsGatewayServer itself if unset here -- see that file's own header for the exact
  // default values and reasoning.
  const idleTimeoutMs = process.env.GPS_GATEWAY_IDLE_TIMEOUT_MS !== undefined ? Number(process.env.GPS_GATEWAY_IDLE_TIMEOUT_MS) : undefined;
  const maxConnections = process.env.GPS_GATEWAY_MAX_CONNECTIONS !== undefined ? Number(process.env.GPS_GATEWAY_MAX_CONNECTIONS) : undefined;

  const ingestClient = new GpsGatewayIngestClient(supabaseUrl, supabaseServiceRoleKey, rawApiKey, gatewayInstanceLabel);
  const buffer = new DurableTelemetryBuffer(bufferFilePath);

  const server = new GpsGatewayServer({
    ingestClient,
    buffer,
    gatewayInstanceLabel,
    onLog: (line) => log("info", line),
    idleTimeoutMs,
    maxConnections,
  });

  let ready = false;
  const health = new HealthServer({
    getMetrics: () => server.metrics,
    getReady: () => ready,
  });

  const flushTimer = setInterval(() => {
    buffer
      .flush(ingestClient)
      .then(({ flushedCount, deadLettered, quarantinedLineCount }) => {
        if (flushedCount > 0) {
          log("info", "durable buffer flush", { flushedCount });
        }
        // ATW-031 (ISS-2026-030): a line that could not be parsed at all -- the signature
        // of a crash mid-append. It no longer wedges every future flush; it is moved to
        // the `.corrupt` sidecar and reported here. This is real telemetry lost before it
        // was ever durable, so it logs at error, never info.
        if (quarantinedLineCount > 0) {
          log("error", "durable buffer quarantined unparseable line(s)", {
            quarantinedLineCount,
            corruptFilePath: buffer.corruptFilePath,
          });
        }
        // ATW-246 (poison-pill finding): a permanently-failing batch no longer blocks
        // every other device's own telemetry -- it is skipped and reported here instead,
        // one clear log line per dead-lettered batch, never a silent drop.
        for (const batch of deadLettered) {
          log("error", "durable buffer dead-lettered a permanently-failing batch", {
            deviceId: batch.deviceId,
            reportCount: batch.reportCount,
            enqueuedAt: batch.enqueuedAt,
            reason: batch.reason,
          });
        }
      })
      .catch((error: Error) => log("error", "durable buffer flush failed", { error: error.message }));
  }, flushIntervalMs);

  await server.listen(tcpPort, tcpHost);
  await health.listen(healthPort, healthHost);
  ready = true;
  log("info", "gps-gateway started", { tcpPort, tcpHost, healthPort });

  const shutdown = async (signal: string) => {
    log("info", "gps-gateway shutting down", { signal });
    ready = false;
    clearInterval(flushTimer);
    await Promise.all([server.close(), health.close()]);
    process.exit(0);
  };
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));
}

main().catch((error: Error) => {
  log("error", "gps-gateway failed to start", { error: error.message });
  process.exit(1);
});
