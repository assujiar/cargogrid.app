/**
 * Durable local buffering (226_GPS_TELEMATICS_INTEGRATION_PROMPT.md §14B: "durable
 * buffering") for GPS Gateway telemetry batches, so a transient loss of connectivity to
 * Supabase never drops an already-decoded AVL packet. An append-only, newline-delimited
 * JSON file on local disk -- deliberately not an in-memory-only queue (a process
 * restart mid-outage would silently lose every buffered batch) and deliberately not
 * app.jobs (PLT-131/132) -- see this checkpoint's own migration header design note 5 for
 * why the buffer genuinely lives at the edge, in this package, not centrally in Postgres.
 *
 * Each pending entry is flushed in enqueue order (never reordered -- a device's own
 * telemetry history must stay chronological); a failed flush attempt stops the whole
 * flush pass immediately (the entry, and everything enqueued after it, stays buffered)
 * rather than skipping ahead and re-attempting out of order.
 */

import { appendFile, readFile, writeFile, rename, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import type { GatewayIngestReport, GpsGatewayIngestClientLike } from "./ingestClient.ts";

export interface BufferedBatch {
  deviceId: string;
  reports: GatewayIngestReport[];
  enqueuedAt: string;
}

export class DurableTelemetryBuffer {
  private readonly filePath: string;
  private flushing = false;

  constructor(filePath: string) {
    this.filePath = filePath;
  }

  async enqueue(batch: BufferedBatch): Promise<void> {
    await mkdir(dirname(this.filePath), { recursive: true });
    await appendFile(this.filePath, `${JSON.stringify(batch)}\n`, "utf8");
  }

  private async readPending(): Promise<BufferedBatch[]> {
    let raw: string;
    try {
      raw = await readFile(this.filePath, "utf8");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        return [];
      }
      throw error;
    }
    return raw
      .split("\n")
      .filter((line) => line.trim().length > 0)
      .map((line) => JSON.parse(line) as BufferedBatch);
  }

  private async writePending(batches: BufferedBatch[]): Promise<void> {
    const tempPath = `${this.filePath}.tmp`;
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(tempPath, batches.map((batch) => JSON.stringify(batch)).join("\n") + (batches.length > 0 ? "\n" : ""), "utf8");
    await rename(tempPath, this.filePath);
  }

  /** Attempts to flush every currently-pending batch, oldest first, stopping at the first failure. Returns the count actually flushed. Re-entrant calls while a flush is already running are a no-op (returns 0) -- never two concurrent writers racing the same buffer file. */
  async flush(client: GpsGatewayIngestClientLike): Promise<number> {
    if (this.flushing) {
      return 0;
    }
    this.flushing = true;
    try {
      const pending = await this.readPending();
      let flushedCount = 0;
      for (const batch of pending) {
        try {
          await client.ingestBatch(batch.deviceId, batch.reports);
          flushedCount += 1;
        } catch {
          break;
        }
      }
      if (flushedCount > 0) {
        await this.writePending(pending.slice(flushedCount));
      }
      return flushedCount;
    } finally {
      this.flushing = false;
    }
  }

  async pendingCount(): Promise<number> {
    return (await this.readPending()).length;
  }
}
