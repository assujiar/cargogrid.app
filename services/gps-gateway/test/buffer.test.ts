import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, appendFile, readFile } from "node:fs/promises";
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

/** ATW-031: variant exposing the raw queue path, so a test can simulate a torn append. */
async function withTempBufferPath<T>(
  fn: (buffer: DurableTelemetryBuffer, bufferPath: string) => Promise<T>,
): Promise<T> {
  const dir = await mkdtemp(join(tmpdir(), "gps-gateway-buffer-test-"));
  const bufferPath = join(dir, "buffer.jsonl");
  try {
    return await fn(new DurableTelemetryBuffer(bufferPath), bufferPath);
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

    const outcome = await buffer.flush(fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => ({ deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" })));
    assert.equal(outcome.flushedCount, 1);
    assert.deepEqual(outcome.deadLettered, []);
    assert.equal(await buffer.pendingCount(), 0);
  });
});

test("a TRANSIENT flush failure (e.g. network/unreachable) on the first pending batch leaves every batch (including later ones) still buffered, in order -- unchanged pre-existing halt-and-retry behavior", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-1", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:00Z" });
    await buffer.enqueue({ deviceId: "device-2", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:01Z" });

    const outcome = await buffer.flush(
      fakeClient(async () => {
        throw new Error("still unreachable");
      }),
    );
    assert.equal(outcome.flushedCount, 0);
    assert.deepEqual(outcome.deadLettered, []);
    assert.equal(await buffer.pendingCount(), 2);
  });
});

test("a TRANSIENT flush failure that succeeds on the first batch and fails on the second retains only the second", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-1", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:00Z" });
    await buffer.enqueue({ deviceId: "device-2", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:01Z" });

    let calls = 0;
    const outcome = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        calls += 1;
        if (calls === 2) {
          throw new Error("fails on the second");
        }
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );
    assert.equal(outcome.flushedCount, 1);
    assert.deepEqual(outcome.deadLettered, []);
    assert.equal(await buffer.pendingCount(), 1);
  });
});

test("a concurrent flush call while one is already in progress is a no-op (returns zero counts, never races the buffer file)", async () => {
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
    assert.equal(secondFlush.flushedCount, 0);
    assert.deepEqual(secondFlush.deadLettered, []);
    const first = await firstFlush;
    assert.equal(first.flushedCount, 1);
  });
});

// ATW-246 finding 3 (HIGH, poison-pill): reproduces the exact probe scenario -- a
// permanently-failing batch for device A (queued first) must no longer block device B's
// own, later-queued, healthy batch from flushing in the same pass. Before this fix,
// `flush()` `catch { break; }`'d on the very first failure regardless of its kind, so
// device A's permanent rejection (e.g. it was suspended mid-flight, the real
// `app.ingest_direct_device_telemetry_batch` `device_not_ingestible` rejection) would
// have permanently starved every other device sharing this one gateway process's buffer.
test("ATW-246 finding 3: a PERMANENT failure (device_not_ingestible) for device A does not block device B's later-queued healthy batch -- device A is dead-lettered, not retried, device B still flushes", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-A-suspended", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:00Z" });
    await buffer.enqueue({ deviceId: "device-B-healthy", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:01Z" });
    assert.equal(await buffer.pendingCount(), 2);

    const outcome = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        if (deviceId === "device-A-suspended") {
          // The exact shape app.ingest_direct_device_telemetry_batch raises for a
          // device that became not-ingestible mid-flight (supabase/migrations/
          // 20260729390000_..._canonical_telemetry_arbitration.sql).
          throw new Error("device_not_ingestible: device device-A-suspended is suspended and cannot accept telemetry");
        }
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );

    assert.equal(outcome.flushedCount, 1, "device B's healthy batch must still flush despite device A's permanent failure");
    assert.equal(outcome.deadLettered.length, 1, "device A's permanently-failing batch must be reported as dead-lettered, not silently dropped");
    assert.equal(outcome.deadLettered[0]?.deviceId, "device-A-suspended");
    assert.match(outcome.deadLettered[0]?.reason ?? "", /^device_not_ingestible:/);

    // Device A's own poison-pill batch is gone from the persisted queue (dead-lettered,
    // never retried -- retrying identical bytes against an identical device_not_
    // ingestible state would fail identically forever); device B's batch is also gone
    // (it flushed successfully). The buffer is fully drained.
    assert.equal(await buffer.pendingCount(), 0);
  });
});

test("ATW-246 finding 3: a PERMANENT failure for a later batch still lets every earlier, already-flushed batch count as flushed, and a TRANSIENT failure after a dead-letter still halts the remainder", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-healthy-1", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:00Z" });
    await buffer.enqueue({ deviceId: "device-bad-tenant", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:01Z" });
    await buffer.enqueue({ deviceId: "device-network-blip", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:02Z" });
    await buffer.enqueue({ deviceId: "device-never-reached", reports: [REPORT], enqueuedAt: "2026-08-03T00:00:03Z" });

    const outcome = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        if (deviceId === "device-bad-tenant") {
          throw new Error("tenant_mismatch: device device-bad-tenant belongs to a different tenant than the presented API key");
        }
        if (deviceId === "device-network-blip") {
          throw new Error("fetch failed");
        }
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );

    assert.equal(outcome.flushedCount, 1);
    assert.equal(outcome.deadLettered.length, 1);
    assert.equal(outcome.deadLettered[0]?.deviceId, "device-bad-tenant");

    // device-network-blip (transient) halts the pass -- it and device-never-reached
    // (queued after it) both remain buffered, in order, for the next attempt.
    const stillPending = await buffer.pendingCount();
    assert.equal(stillPending, 2);
  });
});

test("ATW-030: a batch enqueued while a flush is in flight survives the flush's own queue rewrite", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-already-buffered", reports: [REPORT], enqueuedAt: "2026-08-05T00:00:00Z" });

    // The live socket path fails over and buffers a NEW batch while this flush is still
    // awaiting its own ingest round-trip -- the exact window the previous whole-file
    // overwrite silently destroyed.
    let enqueuedDuringFlush = false;
    const outcome = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        if (!enqueuedDuringFlush) {
          enqueuedDuringFlush = true;
          await buffer.enqueue({ deviceId: "device-enqueued-mid-flush", reports: [REPORT], enqueuedAt: "2026-08-05T00:00:01Z" });
        }
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );

    assert.equal(enqueuedDuringFlush, true, "the mid-flush enqueue must actually have run");
    assert.equal(outcome.flushedCount, 1);
    assert.equal(outcome.deadLettered.length, 0);
    // The mid-flush batch is still queued -- never ingested by this pass, never destroyed.
    assert.equal(await buffer.pendingCount(), 1);

    const nextPass: string[] = [];
    const second = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        nextPass.push(deviceId);
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );
    assert.equal(second.flushedCount, 1);
    assert.deepEqual(nextPass, ["device-enqueued-mid-flush"]);
    assert.equal(await buffer.pendingCount(), 0);
  });
});

test("ATW-030: a batch enqueued while a flush is HALTED by a transient failure is retained behind the halted batch, in order", async () => {
  await withTempBuffer(async (buffer) => {
    await buffer.enqueue({ deviceId: "device-network-blip", reports: [REPORT], enqueuedAt: "2026-08-05T00:00:00Z" });

    let enqueuedDuringFlush = false;
    const outcome = await buffer.flush(
      fakeClient(async (deviceId): Promise<IngestBatchResult> => {
        if (!enqueuedDuringFlush) {
          enqueuedDuringFlush = true;
          await buffer.enqueue({ deviceId: "device-enqueued-mid-halt", reports: [REPORT], enqueuedAt: "2026-08-05T00:00:01Z" });
        }
        throw new Error(`fetch failed for ${deviceId}`);
      }),
    );

    assert.equal(outcome.flushedCount, 0);
    // Nothing flushed and nothing dead-lettered means no rewrite happened at all, so both
    // the halted batch and the mid-flush arrival are still queued, oldest first.
    assert.equal(await buffer.pendingCount(), 2);

    const order: string[] = [];
    await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        order.push(deviceId);
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );
    assert.deepEqual(order, ["device-network-blip", "device-enqueued-mid-halt"]);
  });
});

test("ATW-031 (ISS-2026-030): a torn final line does NOT wedge the buffer -- intact batches still flush and the damaged line is quarantined", async () => {
  await withTempBufferPath(async (buffer, bufferPath) => {
    await buffer.enqueue({ deviceId: "device-intact-1", reports: [REPORT], enqueuedAt: "2026-08-05T00:00:00Z" });
    await buffer.enqueue({ deviceId: "device-intact-2", reports: [REPORT], enqueuedAt: "2026-08-05T00:00:01Z" });
    // Simulate a crash part-way through appendFile: a truncated, unparseable final line.
    await appendFile(bufferPath, '{"deviceId":"device-torn","reports":[{"reportTy', "utf8");

    // Before ATW-031 this threw straight out of readPending() and every subsequent call
    // threw with it, permanently.
    assert.equal(await buffer.pendingCount(), 2, "the two intact batches are still countable");

    const flushed: string[] = [];
    const outcome = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        flushed.push(deviceId);
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );

    assert.deepEqual(flushed, ["device-intact-1", "device-intact-2"], "both intact batches flushed, in order");
    assert.equal(outcome.flushedCount, 2);
    assert.equal(outcome.quarantinedLineCount, 1, "the torn line is reported, never silently dropped");
    assert.equal(await buffer.pendingCount(), 0, "the torn line is removed from the live queue");

    // The bytes are preserved on disk for forensics.
    const corrupt = await readFile(buffer.corruptFilePath, "utf8");
    assert.match(corrupt, /device-torn/);
  });
});

test("ATW-031: a syntactically valid line that is not a batch is quarantined too, never handed to ingestBatch", async () => {
  await withTempBufferPath(async (buffer, bufferPath) => {
    await buffer.enqueue({ deviceId: "device-ok", reports: [REPORT], enqueuedAt: "2026-08-05T00:00:00Z" });
    // Valid JSON, wrong shape -- ingestBatch(undefined, undefined) would fail forever.
    await appendFile(bufferPath, '{"unexpected":"shape"}\n[1,2,3]\n"a string"\n', "utf8");

    const seen: unknown[] = [];
    const outcome = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => {
        seen.push(deviceId);
        return { deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active" };
      }),
    );

    assert.deepEqual(seen, ["device-ok"], "only the real batch reached ingest");
    assert.equal(outcome.quarantinedLineCount, 3);
    assert.equal(await buffer.pendingCount(), 0);
  });
});

test("ATW-031: a buffer file that is ENTIRELY corrupt still drains rather than throwing forever", async () => {
  await withTempBufferPath(async (buffer, bufferPath) => {
    await appendFile(bufferPath, '{"broken\n{"also broken\n', "utf8");

    assert.equal(await buffer.pendingCount(), 0);
    const outcome = await buffer.flush(
      fakeClient(async (deviceId, reports): Promise<IngestBatchResult> => ({
        deviceId, tenantId: "tenant-1", acceptedCount: reports.length, deviceStatus: "active",
      })),
    );
    assert.equal(outcome.flushedCount, 0);
    assert.equal(outcome.quarantinedLineCount, 2);
    // The queue is now genuinely empty, not permanently poisoned.
    assert.equal(await buffer.pendingCount(), 0);
    assert.match(await readFile(buffer.corruptFilePath, "utf8"), /also broken/);
  });
});
