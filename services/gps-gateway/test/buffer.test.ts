import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DurableTelemetryBuffer } from "../src/buffer.ts";
import type { GpsGatewayIngestClientLike, IngestBatchResult, HandshakeResult, GatewayIngestReport } from "../src/ingestClient.ts";

async function withTempBuffer<T>(fn: (buffer: DurableTelemetryBuffer) => Promise<T>): Promise<T> {
  const dir = await mkdtemp(join(tmpdir(), "gps-gateway-buffer-test-"));
  try {
    return await fn(new DurableTelemetryBuffer(join(dir, "buffer.jsonl")));
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

const REPORT: GatewayIngestReport = {
  reportType: "heartbeat",
  eventAt: "2026-08-03T00:00:00Z",
  longitude: null,
  latitude: null,
  altitudeMeters: null,
  headingDegrees: null,
  speedKmh: null,
  satelliteCount: null,
  rawCodecId: "8E",
  ioElements: {},
};

function fakeClient(ingestBatch: GpsGatewayIngestClientLike["ingestBatch"]): GpsGatewayIngestClientLike {
  return {
    resolveHandshake: async (): Promise<HandshakeResult> => ({ accepted: true, deviceId: "device-1", tenantId: "tenant-1", rejectionReason: null }),
    ingestBatch,
  };
}

test("pendingCount is 0 for a buffer file that has never been written", async () => {
  await withTempBuffer(async (buffer) => {
    assert.equal(await buffer.pendingCount(), 0);
  });
});

test("enqueue then flush: a successful ingest drains the buffer to empty", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-1", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:00Z" });
    assert.equal(await buffer.pendingCount(), 1);

    const flushed = await buffer.flush(fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => ({ deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" })));
    assert.equal(flushed, 1);
    assert.equal(await buffer.pendingCount(), 0);
  });
});

test("a flush failure on the first pending batch leaves every batch (including later ones) still buffered, in order", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-1", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:00Z" });
    await buffer.enqueue({ deviceId: "device-2", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:01Z" });

    const flushed = await buffer.flush(
      fakeClient(async () => {
        throw new Error("still unreachable");
      }),
    );
    assert.equal(flushed, 0);
    assert.equal(await buffer.pendingCount(), 2);
  });
});

test("a flush that succeeds on the first batch and fails on the second retains only the second", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-1", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:00Z" });
    await buffer.enqueue({ deviceId: "device-2", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:01Z" });

    let calls = 0;
    const flushed = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        calls += 1;
        if (calls === 2) {
          throw new Error("fails on the second");
        }
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );
    assert.equal(flushed, 1);
    assert.equal(await buffer.pendingCount(), 1);
  });
});

test("a concurrent flush call while one is already in progress is a no-op (returns 0, never races the buffer file)", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-1", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:00Z" });

    let resolveIngest: (() => void) | undefined;
    const ingestStarted = new Promise<void>((resolve) => {
      resolveIngest = resolve;
    });
    const client = fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
      resolveIngest?.();
      await new Promise((r) => setTimeout(r, 20));
      return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
    });

    const firstFlush = buffer.flush(client);
    await ingestStarted;
    const secondFlush = await buffer.flush(client);
    assert.equal(secondFlush, 0);
    assert.equal(await firstFlush, 1);
  });
});
