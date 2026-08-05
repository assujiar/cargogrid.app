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
 * telemetry history must stay chronological). ATW-246 hardening (poison-pill finding):
 * a failure is classified as either PERMANENT (the batch is structurally invalid, or the
 * owning device/tenant is in a state the server will never accept from -- see
 * `isPermanentIngestFailure` below) or TRANSIENT (anything else, presumed a network/
 * connectivity-class failure). A permanent failure for one device's batch is skipped
 * (dead-lettered: removed from the persisted queue, never retried, reported back to the
 * caller for logging) so every OTHER device's own batches sharing this one buffer file
 * keep flushing -- one device going permanently bad (e.g. suspended mid-flight,
 * `device_not_ingestible`) no longer blocks the whole gateway process's telemetry
 * indefinitely. A transient failure still halts the whole pass at that point (the entry,
 * and everything enqueued after it, stays buffered) to preserve strict per-flush-pass
 * ordering for the genuinely-recoverable case -- unchanged from the original behavior.
 */

import { appendFile, readFile, writeFile, rename, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import type { GatewayIngestReport, GpsGatewayIngestClientLike } from "./ingestClient.ts";

export interface BufferedBatch {
  deviceId: string;
  reports: GatewayIngestReport[];
  enqueuedAt: string;
}

export interface DeadLetteredBatch {
  deviceId: string;
  reportCount: number;
  enqueuedAt: string;
  reason: string;
}

export interface FlushOutcome {
  /** Count of batches successfully ingested this pass. */
  flushedCount: number;
  /** Batches permanently, non-retryably rejected this pass -- removed from the queue, never retried. */
  deadLettered: DeadLetteredBatch[];
}

// ATW-246 hardening: the exact set of app.ingest_direct_device_telemetry_batch's own
// `raise exception '<code>: ...'` prefixes that are structurally non-retryable --
// retrying the identical bytes against the identical device/tenant state will fail
// identically every time (supabase/migrations/20260729370000_create_advanced_tms_gps_
// gateway_ingestion.sql, widened at .../20260729390000_..._canonical_telemetry_
// arbitration.sql -- neither edited by this repair). Deliberately does NOT include
// `insufficient_authority` (a broken/revoked gateway API key is a GATEWAY-WIDE problem,
// not a per-device one -- misclassifying it as "permanent" would silently dead-letter
// every device's telemetry forever instead of correctly halting-and-alerting, so it
// stays in the default TRANSIENT bucket below). Anything not matching this allowlist
// defaults to TRANSIENT (halt-and-retry) -- the safe default, since misclassifying a
// real transient failure as permanent would silently drop real telemetry, while the
// reverse (a permanent failure kept as transient) only reproduces this finding's own
// pre-existing behavior for that one unclassified reason, never a new regression.
const PERMANENT_INGEST_FAILURE_REASON_PATTERN =
  /^(device_not_ingestible|tenant_mismatch|device_not_found|reports_required|device_id_required|invalid_report_type|event_at_required|location_required):/;

function permanentFailureReason(error: unknown): string | null {
  if (error instanceof Error && PERMANENT_INGEST_FAILURE_REASON_PATTERN.test(error.message)) {
    return error.message;
  }
  return null;
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

  private async readRaw(): Promise<string> {
    try {
      return await readFile(this.filePath, "utf8");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        return "";
      }
      throw error;
    }
  }

  private static parse(raw: string): BufferedBatch[] {
    return raw
      .split("\n")
      .filter((line) => line.trim().length > 0)
      .map((line) => JSON.parse(line) as BufferedBatch);
  }

  private async readPending(): Promise<BufferedBatch[]> {
    return DurableTelemetryBuffer.parse(await this.readRaw());
  }

  /**
   * ATW-030: rewrites the queue to `batches` WITHOUT destroying anything `enqueue()`
   * appended while the flush was in flight.
   *
   * `flush()` necessarily awaits a real ingest round-trip per batch, and `enqueue()` is
   * called on the live socket path during exactly that window whenever an ingest fails
   * over to the buffer. The previous whole-file overwrite replaced the file with only
   * the retained snapshot, silently destroying every batch appended in between -- a
   * durable-buffer implementation losing precisely the telemetry it exists to protect.
   *
   * `snapshotByteLength` is the byte length this pass originally read. Anything beyond
   * it is an append that arrived since, so it is carried over verbatim (appends are
   * O_APPEND whole-line writes, so the tail is always a clean line boundary).
   */
  private async writePending(batches: BufferedBatch[], snapshotByteLength: number): Promise<void> {
    const currentRaw = await this.readRaw();
    const appendedSinceSnapshot = Buffer.from(currentRaw, "utf8").subarray(snapshotByteLength).toString("utf8");

    const retained = batches.map((batch) => JSON.stringify(batch)).join("\n") + (batches.length > 0 ? "\n" : "");
    const next = retained + appendedSinceSnapshot;

    const tempPath = `${this.filePath}.tmp`;
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(tempPath, next, "utf8");
    await rename(tempPath, this.filePath);
  }

  /**
   * Attempts to flush every currently-pending batch, oldest first. A PERMANENT failure
   * (see `PERMANENT_INGEST_FAILURE_REASON_PATTERN`) is skipped -- dead-lettered, removed
   * from the persisted queue -- and the pass continues past it; a TRANSIENT failure still
   * stops the whole pass at that point (that entry, and everything enqueued after it,
   * stays buffered, oldest-first ordering preserved for the next attempt). Re-entrant
   * calls while a flush is already running are a no-op (returns zero counts) -- never two
   * concurrent writers racing the same buffer file.
   */
  async flush(client: GpsGatewayIngestClientLike): Promise<FlushOutcome> {
    if (this.flushing) {
      return { flushedCount: 0, deadLettered: [] };
    }
    this.flushing = true;
    try {
      // ATW-030: capture the exact byte length this pass is responsible for, so
      // writePending() can carry over anything enqueue() appends during the flush.
      const snapshotRaw = await this.readRaw();
      const snapshotByteLength = Buffer.byteLength(snapshotRaw, "utf8");
      const pending = DurableTelemetryBuffer.parse(snapshotRaw);
      const retained: BufferedBatch[] = [];
      const deadLettered: DeadLetteredBatch[] = [];
      let flushedCount = 0;
      let halted = false;

      for (const batch of pending) {
        if (halted) {
          retained.push(batch);
          continue;
        }
        try {
          await client.ingestBatch(batch.deviceId, batch.reports);
          flushedCount += 1;
        } catch (error) {
          const permanentReason = permanentFailureReason(error);
          if (permanentReason !== null) {
            deadLettered.push({
              deviceId: batch.deviceId,
              reportCount: batch.reports.length,
              enqueuedAt: batch.enqueuedAt,
              reason: permanentReason,
            });
            // Skip-and-continue -- do not retain, do not halt. Every other device's own
            // batches, including ones enqueued after this one, still get a chance to
            // flush this same pass.
          } else {
            halted = true;
            retained.push(batch);
          }
        }
      }

      if (flushedCount > 0 || deadLettered.length > 0) {
        await this.writePending(retained, snapshotByteLength);
      }
      return { flushedCount, deadLettered };
    } finally {
      this.flushing = false;
    }
  }

  async pendingCount(): Promise<number> {
    return (await this.readPending()).length;
  }
}
