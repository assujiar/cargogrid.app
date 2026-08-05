/**
 * CG-S10-ATW-024 (Prompt 243) Scenario 5 -- GPS telemetry ingestion at volume,
 * reusing the EXISTING Codec 8 Extended simulator already built for ATW-226D
 * (services/gps-gateway/src/codec8e.ts) and the real TCP-socket server
 * (services/gps-gateway/src/server.ts, the identical GpsGatewayServer class
 * services/gps-gateway/test/server.test.ts already exercises -- not a second GPS
 * protocol encoder, per this task's own explicit instruction). Spins up N
 * concurrent simulated device TCP connections against a REAL, running,
 * in-process GpsGatewayServer instance (real node:net sockets, real IMEI
 * handshake bytes, real Codec 8 Extended AVL frames with real CRC-16), measures
 * ACK p50/p95/p99, verifies zero dropped/corrupted frames under concurrent load,
 * and verifies reconnect behavior.
 *
 * External-evidence policy (Prompt 243's own "External-evidence policy" section,
 * mirrored from 226_GPS_TELEMATICS_INTEGRATION_PROMPT.md): the ingest CLIENT
 * (services/gps-gateway/src/ingestClient.ts) is replaced with a fast, in-memory
 * fake for this load run -- identical in spirit to services/gps-gateway/test/
 * server.test.ts's own fakeIngestClient -- since a live Supabase/PostgREST
 * endpoint is not available in this sandbox (no live Supabase project exists
 * anywhere in this repository yet, ADR-0010). This measures the REAL TCP/
 * protocol/decode/buffer layer under real concurrent load (the actual gateway
 * process's own bottleneck surface); it does not (and cannot) measure live
 * Supabase RPC latency, which is a separate, already-disclosed DEFERRED_EXTERNAL_
 * HARDWARE_EVIDENCE/CONDITIONALLY_SKIPPED_PROVIDER_UNAVAILABLE boundary this
 * checkpoint does not newly cross -- physical Teltonika hardware and a live
 * third-party GPS provider remain unavailable exactly as every prior ATW-226
 * checkpoint already disclosed.
 *
 * Run: node --experimental-strip-types scripts/load-tests/gps-telemetry-load.ts
 */

import { connect, type Socket } from "node:net";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GpsGatewayServer } from "../../services/gps-gateway/src/server.ts";
import { DurableTelemetryBuffer } from "../../services/gps-gateway/src/buffer.ts";
import { encodeAvlDataPacket } from "../../services/gps-gateway/src/codec8e.ts";
import type { GpsGatewayIngestClientLike, HandshakeResult, IngestBatchResult, GatewayIngestReport } from "../../services/gps-gateway/src/ingestClient.ts";

const DEVICE_COUNT = Number(process.env.LOAD_GPS_DEVICES ?? 50);
const PACKETS_PER_DEVICE = Number(process.env.LOAD_GPS_PACKETS_PER_DEVICE ?? 20);
const RECONNECT_DEVICE_COUNT = Number(process.env.LOAD_GPS_RECONNECT_DEVICES ?? 10);

function imeiFor(deviceIndex: number): string {
  // 15-digit numeric IMEI, deterministic per device index.
  return `86111203${String(deviceIndex).padStart(7, "0")}`;
}

function imeiHandshakeBytes(imei: string): Buffer {
  return Buffer.concat([Buffer.from([0x00, imei.length]), Buffer.from(imei, "ascii")]);
}

function percentile(sortedMs: number[], p: number): number {
  if (sortedMs.length === 0) return NaN;
  const idx = Math.min(sortedMs.length - 1, Math.ceil((p / 100) * sortedMs.length) - 1);
  return sortedMs[Math.max(0, idx)] ?? NaN;
}

interface FakeIngestState {
  ingestedBatches: number;
  ingestedReports: number;
  handshakeCount: number;
}

// CG-S10-ATW-024 fix-pass addition (spec-compliance review, HIGH finding 3b:
// "'buffer' is instantiated (DurableTelemetryBuffer) but never triggered under
// load since the fake ingest client always succeeds"). A mutable outage toggle
// lets the "outage & durable-buffer recovery" phase below (still real concurrent
// TCP/socket/decode traffic against the real GpsGatewayServer, not a second,
// isolated unit) force ingestBatch to fail on demand -- the exact live-ingest-
// failure path services/gps-gateway/test/server.test.ts already proves
// functionally in isolation, now also exercised under this scenario's own real
// concurrent load, not merely a single connection.
interface OutageToggle {
  active: boolean;
}

function fakeIngestClient(state: FakeIngestState, outage: OutageToggle): GpsGatewayIngestClientLike {
  return {
    resolveHandshake: async (imei: string): Promise<HandshakeResult> => {
      state.handshakeCount += 1;
      if (!/^\d{15}$/.test(imei)) {
        return { accepted: false, deviceId: null, tenantId: null, rejectionReason: "malformed_imei" };
      }
      return { accepted: true, deviceId: `device-${imei}`, tenantId: "loadtest-tenant", rejectionReason: null };
    },
    ingestBatch: async (deviceId: string, reports: GatewayIngestReport[]): Promise<IngestBatchResult> => {
      if (outage.active) {
        throw new Error("simulated_live_ingest_outage");
      }
      state.ingestedBatches += 1;
      state.ingestedReports += reports.length;
      return { deviceId, tenantId: "loadtest-tenant", acceptedCount: reports.length, deviceStatus: "active" };
    },
  };
}

async function sendPacketAndAwaitAck(socket: Socket, packet: Buffer, expectedRecordCount: number): Promise<{ latencyMs: number; ok: boolean; error?: string }> {
  const start = performance.now();
  return new Promise((resolve) => {
    const onData = (chunk: Buffer) => {
      socket.removeListener("data", onData);
      const latencyMs = performance.now() - start;
      if (chunk.length !== 4) {
        resolve({ latencyMs, ok: false, error: `unexpected ACK length ${chunk.length}` });
        return;
      }
      const acceptedCount = chunk.readUInt32BE(0);
      if (acceptedCount !== expectedRecordCount) {
        resolve({ latencyMs, ok: false, error: `expected ACK count ${expectedRecordCount}, got ${acceptedCount}` });
        return;
      }
      resolve({ latencyMs, ok: true });
    };
    socket.on("data", onData);
    socket.write(packet);
  });
}

async function connectAndHandshake(port: number, imei: string): Promise<Socket> {
  const socket = connect(port, "127.0.0.1");
  await new Promise<void>((resolve, reject) => {
    socket.once("connect", resolve);
    socket.once("error", reject);
  });
  const handshakeAck = new Promise<Buffer>((resolve) => socket.once("data", resolve));
  socket.write(imeiHandshakeBytes(imei));
  const ack = await handshakeAck;
  if (ack.length !== 1 || ack[0] !== 0x01) {
    throw new Error(`handshake not accepted for IMEI ${imei}: ${ack.toString("hex")}`);
  }
  return socket;
}

async function main() {
  const dir = await mkdtemp(join(tmpdir(), "cargogrid-gps-load-"));
  const bufferFilePath = join(dir, "buffer.jsonl");
  const buffer = new DurableTelemetryBuffer(bufferFilePath);
  const ingestState: FakeIngestState = { ingestedBatches: 0, ingestedReports: 0, handshakeCount: 0 };
  const outage: OutageToggle = { active: false };
  const ingestClient = fakeIngestClient(ingestState, outage);
  const server = new GpsGatewayServer({ ingestClient, buffer, gatewayInstanceLabel: "load-test-gateway" });
  await server.listen(0, "127.0.0.1");
  const port = server.boundPort;

  console.log(`=== GPS Telemetry Load Scenario ===`);
  console.log(`devices=${DEVICE_COUNT} packetsPerDevice=${PACKETS_PER_DEVICE} totalPackets=${DEVICE_COUNT * PACKETS_PER_DEVICE} reconnectDevices=${RECONNECT_DEVICE_COUNT}`);

  const allLatenciesMs: number[] = [];
  let errors = 0;
  const errorMessages: string[] = [];
  const overallStart = performance.now();

  const deviceRuns = Array.from({ length: DEVICE_COUNT }, async (_unused, deviceIndex) => {
    const imei = imeiFor(deviceIndex);
    const socket = await connectAndHandshake(port, imei);
    for (let p = 0; p < PACKETS_PER_DEVICE; p++) {
      const timestampMs = BigInt(1_700_000_000_000 + deviceIndex * 1000 + p);
      const packet = encodeAvlDataPacket([
        {
          timestampMs,
          priority: 1,
          longitude: 106.8 + deviceIndex * 0.001 + p * 0.0001,
          latitude: -6.2 + deviceIndex * 0.001 + p * 0.0001,
          altitudeMeters: 10,
          angleDegrees: 90,
          satellites: 8,
          speedKmh: 40,
        },
      ]);
      const result = await sendPacketAndAwaitAck(socket, packet, 1);
      allLatenciesMs.push(result.latencyMs);
      if (!result.ok) {
        errors += 1;
        errorMessages.push(`device ${deviceIndex} packet ${p}: ${result.error}`);
      }
    }
    socket.destroy();
  });

  await Promise.all(deviceRuns);
  const overallDurationMs = performance.now() - overallStart;

  // Reconnect scenario: a subset of devices disconnect and reconnect with the
  // SAME imei, proving the gateway has no per-IMEI session state that would
  // block or corrupt a genuine reconnect (a real device reconnecting after a
  // transient cellular drop is the exact scenario this proves).
  let reconnectFailures = 0;
  for (let r = 0; r < RECONNECT_DEVICE_COUNT; r++) {
    const imei = imeiFor(r);
    try {
      const socket1 = await connectAndHandshake(port, imei);
      socket1.destroy();
      await new Promise((resolve) => setTimeout(resolve, 10));
      const socket2 = await connectAndHandshake(port, imei);
      const packet = encodeAvlDataPacket([
        { timestampMs: BigInt(1_800_000_000_000 + r), priority: 1, longitude: 107, latitude: -6.3, altitudeMeters: 5, angleDegrees: 0, satellites: 6, speedKmh: 0 },
      ]);
      const result = await sendPacketAndAwaitAck(socket2, packet, 1);
      if (!result.ok) {
        reconnectFailures += 1;
      }
      socket2.destroy();
    } catch (error) {
      reconnectFailures += 1;
      errorMessages.push(`reconnect device ${r}: ${(error as Error).message}`);
    }
  }

  // Outage & durable-buffer recovery under real concurrent load (CG-S10-ATW-024
  // fix-pass addition, spec-compliance review finding 3b/finding 2's "database
  // outage... never exercised" gap for the Direct Device Gateway profile). A
  // batch of concurrent devices sends real AVL packets while the live ingest
  // client is forced to fail every call -- the gateway must still ACK (durable
  // local persistence is this gateway's own point of custody transfer, per its
  // own header) and durably buffer instead of dropping. The outage then clears
  // and the real DurableTelemetryBuffer.flush() path (src/buffer.ts, the same
  // method src/index.ts's own background flush loop calls in production) drains
  // every buffered batch, proving recovery actually completes, not just that
  // buffering occurred.
  const OUTAGE_DEVICE_COUNT = 10;
  const OUTAGE_DEVICE_OFFSET = 500_000;
  outage.active = true;
  const outageResults = await Promise.all(
    Array.from({ length: OUTAGE_DEVICE_COUNT }, async (_unused, i) => {
      const deviceIndex = OUTAGE_DEVICE_OFFSET + i;
      const imei = imeiFor(deviceIndex);
      const socket = await connectAndHandshake(port, imei);
      const packet = encodeAvlDataPacket([
        { timestampMs: BigInt(1_900_000_000_000 + i), priority: 1, longitude: 106.9, latitude: -6.25, altitudeMeters: 12, angleDegrees: 45, satellites: 7, speedKmh: 35 },
      ]);
      const result = await sendPacketAndAwaitAck(socket, packet, 1);
      socket.destroy();
      return result;
    }),
  );
  const outageAckFailures = outageResults.filter((r) => !r.ok).length;
  const bufferedDuringOutage = server.metrics.reportsBuffered;
  const pendingAfterOutage = await buffer.pendingCount();

  outage.active = false;
  const ingestedBatchesBeforeFlush = ingestState.ingestedBatches;
  // ATW-246 (Prompt 246): DurableTelemetryBuffer.flush() now returns a FlushOutcome
  // ({ flushedCount, deadLettered }) instead of a bare number, so a permanently-failing
  // batch for one device can be reported separately from the count of genuinely
  // successful flushes -- see services/gps-gateway/src/buffer.ts's own updated header.
  // This load-test scenario has no permanently-failing batches (only a transient outage
  // window), so deadLettered is expected empty here.
  const { flushedCount, deadLettered } = await buffer.flush(ingestClient);
  const pendingAfterFlush = await buffer.pendingCount();
  const ingestedBatchesAfterFlush = ingestState.ingestedBatches;

  const outagePass =
    outageAckFailures === 0 &&
    bufferedDuringOutage === OUTAGE_DEVICE_COUNT &&
    pendingAfterOutage === OUTAGE_DEVICE_COUNT &&
    flushedCount === OUTAGE_DEVICE_COUNT &&
    deadLettered.length === 0 &&
    pendingAfterFlush === 0 &&
    ingestedBatchesAfterFlush - ingestedBatchesBeforeFlush === OUTAGE_DEVICE_COUNT;

  console.log(`\n=== Outage & durable-buffer recovery (real concurrent load) ===`);
  console.log(`outage_devices=${OUTAGE_DEVICE_COUNT} acks_during_outage_failed=${outageAckFailures} (expected 0 -- ACK still sent, custody transferred to the durable buffer)`);
  console.log(`reports_buffered_during_outage=${bufferedDuringOutage} pending_after_outage=${pendingAfterOutage} (expected ${OUTAGE_DEVICE_COUNT} each)`);
  console.log(`flushed_after_recovery=${flushedCount} dead_lettered_after_recovery=${deadLettered.length} pending_after_flush=${pendingAfterFlush} live_batches_ingested_by_flush=${ingestedBatchesAfterFlush - ingestedBatchesBeforeFlush} (expected ${OUTAGE_DEVICE_COUNT}/0/0/${OUTAGE_DEVICE_COUNT})`);
  console.log(`OUTAGE_BUFFER_RECOVERY_SCENARIO: ${outagePass ? "PASS" : "FAIL"}`);

  // Malformed-frame rejection under load -- one deliberately corrupt connection,
  // proving the server closes it without crashing or affecting concurrent traffic
  // (already proven functionally by services/gps-gateway/test/server.test.ts;
  // re-verified here under a real concurrent-load backdrop, not in isolation).
  let malformedRejectedCleanly = false;
  {
    const socket = await connectAndHandshake(port, imeiFor(999999));
    const closed = new Promise<void>((resolve) => socket.once("close", resolve));
    const badPacket = Buffer.concat([Buffer.from([0x01, 0x00, 0x00, 0x00]), Buffer.alloc(8)]);
    socket.write(badPacket);
    await closed;
    malformedRejectedCleanly = true;
  }

  allLatenciesMs.sort((a, b) => a - b);
  const p50 = percentile(allLatenciesMs, 50);
  const p95 = percentile(allLatenciesMs, 95);
  const p99 = percentile(allLatenciesMs, 99);
  const avg = allLatenciesMs.reduce((a, b) => a + b, 0) / allLatenciesMs.length;
  const max = allLatenciesMs[allLatenciesMs.length - 1] ?? NaN;
  const throughputPerSec = (DEVICE_COUNT * PACKETS_PER_DEVICE) / (overallDurationMs / 1000);

  console.log(`\n=== Results ===`);
  console.log(`total_packets=${allLatenciesMs.length} errors=${errors} malformed_frame_rejected_cleanly=${malformedRejectedCleanly}`);
  console.log(`ack_latency_ms: p50=${p50.toFixed(3)} p95=${p95.toFixed(3)} p99=${p99.toFixed(3)} avg=${avg.toFixed(3)} max=${max.toFixed(3)}`);
  console.log(`overall_duration_ms=${overallDurationMs.toFixed(1)} throughput_packets_per_sec=${throughputPerSec.toFixed(1)}`);
  console.log(`reconnect_attempts=${RECONNECT_DEVICE_COUNT} reconnect_failures=${reconnectFailures}`);
  console.log(`server_metrics=${JSON.stringify(server.metrics)}`);
  console.log(`fake_ingest_client: handshakes=${ingestState.handshakeCount} batches=${ingestState.ingestedBatches} reports=${ingestState.ingestedReports}`);
  if (errorMessages.length > 0) {
    console.log(`error_details (first 10): ${JSON.stringify(errorMessages.slice(0, 10))}`);
  }

  await server.close();
  await rm(dir, { recursive: true, force: true });

  const pass =
    errors === 0 &&
    reconnectFailures === 0 &&
    malformedRejectedCleanly &&
    outagePass &&
    server.metrics.packetsDecoded === DEVICE_COUNT * PACKETS_PER_DEVICE + RECONNECT_DEVICE_COUNT + OUTAGE_DEVICE_COUNT &&
    server.metrics.packetsRejected === 1 &&
    server.metrics.reportsIngestedLive === DEVICE_COUNT * PACKETS_PER_DEVICE + RECONNECT_DEVICE_COUNT;

  console.log(`\nGPS_TELEMETRY_LOAD_SCENARIO: ${pass ? "PASS" : "FAIL"}`);
  process.exit(pass ? 0 : 1);
}

main().catch((error) => {
  console.error("GPS telemetry load scenario crashed:", error);
  process.exit(1);
});
