/**
 * The raw TCP listener (226_GPS_TELEMATICS_INTEGRATION_PROMPT.md §14B) -- IMEI
 * handshake, then a stream of Codec 8 Extended AVL data packets, per connection.
 *
 * Per-connection protocol state machine: `awaiting_handshake` -> (accepted) ->
 * `awaiting_avl_data`. A rejected handshake (unknown/foreign IMEI, wrong-tenant, a
 * device not currently in an ingestible status) gets the single 0x00 reply byte and an
 * immediate socket close -- never left half-open. A malformed or oversized packet
 * (§14B: "malformed/oversized packet rejection") also closes the connection immediately,
 * without an ACK and without crashing the server process -- one bad device/connection
 * never takes down every other concurrent connection.
 *
 * A batch's own live ingest failure (Supabase unreachable, transient error) does not
 * fail the connection or withhold the ACK -- it is durably buffered instead
 * (src/buffer.ts) and the full record count is still ACKed, since durable local
 * persistence is this gateway's own real point of custody transfer: once a batch is on
 * disk, the physical device does not need to hold or retransmit it, and the buffer's own
 * background flush loop (src/index.ts) is what retries the write to Supabase.
 *
 * ATW-246 hardening (finding 2, concurrent-connection impersonation): the raw Teltonika
 * protocol authenticates a device by IMEI alone, and an IMEI is not secret. Two
 * concurrent connections presenting the identical IMEI previously both completed a full
 * handshake -- no exclusivity check existed. This class now tracks in-flight IMEI ->
 * "has an open connection" state in-process (`activeImeis` below) and rejects a second
 * concurrent handshake for an IMEI that already has one open, closing the cheap, always-
 * reproducible half of that finding (see this checkpoint's own migration header,
 * `supabase/migrations/20260730360000_..._device_driver_mobile_tracking.sql`, design
 * note 2, for why in-process state was chosen over a Postgres advisory lock, and for the
 * disclosed, NOT-fully-fixed residual risk this repair does not and cannot close).
 *
 * ATW-246 hardening (finding 6, TCP socket exhaustion): every connection now gets an idle
 * read timeout (`idleTimeoutMs`, closes the socket if no bytes arrive in that window --
 * a device that dials in and then never sends anything, whether accidental or a deliberate
 * slow-connection-flood attempt, no longer holds a socket open forever), and the server
 * enforces a `maxConnections` cap (Node's own `net.Server.maxConnections`, which rejects --
 * destroys, before the `'connection'` handler even runs -- any connection beyond the cap).
 */

import { createServer, type Socket, type Server } from "node:net";
import {
  decodeImeiHandshake,
  encodeHandshakeResponse,
  decodeAvlDataPacket,
  encodeAckResponse,
  type DecodedAvlRecord,
  type Bytes,
} from "./codec8e.ts";
import type { GatewayIngestReport, GpsGatewayIngestClientLike } from "./ingestClient.ts";
import type { DurableTelemetryBuffer } from "./buffer.ts";

const MAX_BUFFERED_BYTES = 65_536;

// ATW-246 finding 6 defaults -- deliberately generous but bounded, overridable via
// GpsGatewayServerOptions (src/index.ts wires GPS_GATEWAY_IDLE_TIMEOUT_MS/
// GPS_GATEWAY_MAX_CONNECTIONS). 60s idle: a real Teltonika device's own configured ping
// interval is typically well under a minute (226_*.md's own §14B target profiles), so a
// genuinely connected, healthy device is never at risk of tripping this; anything idler
// than that is either a dead/hung connection or a scan/probe not worth holding a socket
// open for. 10,000 connections: enough headroom for a large single-tenant-per-gateway
// deployment's own real fleet size while still bounding worst-case file-descriptor/
// memory exhaustion from a connection flood -- see Node's own `net.Server.maxConnections`
// semantics: a connection beyond this cap is destroyed before 'connection' ever fires.
const DEFAULT_IDLE_TIMEOUT_MS = 60_000;
const DEFAULT_MAX_CONNECTIONS = 10_000;

export interface GpsGatewayServerMetrics {
  connectionsOpened: number;
  handshakesAccepted: number;
  handshakesRejected: number;
  packetsDecoded: number;
  packetsRejected: number;
  reportsIngestedLive: number;
  reportsBuffered: number;
}

type ConnectionState =
  | { phase: "awaiting_handshake" }
  | { phase: "awaiting_avl_data"; deviceId: string; imei: string };

/**
 * ATW-030: one connection's own live protocol state, shared by reference between the
 * 'data' handler and every drainAccumulator() call on that connection.
 *
 * Previously the accumulator was a plain closure variable that drainAccumulator()
 * snapshotted on entry and wrote back through a `commit` callback on exit. Because a
 * drain awaits a real ingest round-trip, any chunk arriving during that await was
 * appended to the closure variable and then destroyed by the commit that followed --
 * the bytes were silently dropped, no ACK was ever sent for them, and nothing counted
 * the loss (`packetsRejected` stayed 0). Sharing one mutable holder, and consuming
 * decoded bytes from it BEFORE awaiting rather than after, makes a concurrent append
 * land safely after the already-consumed prefix instead of racing a stale snapshot.
 */
interface ConnectionBuffers {
  accumulator: Bytes;
  state: ConnectionState;
}

function recordToReport(record: DecodedAvlRecord): GatewayIngestReport {
  const hasFix = record.gps.latitude !== 0 || record.gps.longitude !== 0;
  const ioElements: Record<string, string> = {};
  for (const [id, value] of record.io.elements) {
    ioElements[String(id)] = value.toString();
  }
  for (const [id, value] of record.io.variableLengthElements) {
    ioElements[String(id)] = value.toString("hex");
  }
  return {
    reportType: hasFix ? "location" : "heartbeat",
    eventAt: new Date(Number(record.timestampMs)).toISOString(),
    longitude: hasFix ? record.gps.longitude : null,
    latitude: hasFix ? record.gps.latitude : null,
    altitudeMeters: record.gps.altitudeMeters,
    headingDegrees: record.gps.angleDegrees,
    speedKmh: record.gps.speedKmh,
    satelliteCount: record.gps.satellites,
    rawCodecId: "8E",
    ioElements,
  };
}

export interface GpsGatewayServerOptions {
  ingestClient: GpsGatewayIngestClientLike;
  buffer: DurableTelemetryBuffer;
  gatewayInstanceLabel: string;
  onLog?: (line: string) => void;
  /** ATW-246 finding 6: idle-read timeout per connection, milliseconds. Defaults to 60s. */
  idleTimeoutMs?: number;
  /** ATW-246 finding 6: `net.Server.maxConnections`. Defaults to 10,000. */
  maxConnections?: number;
}

export class GpsGatewayServer {
  private readonly server: Server;
  readonly metrics: GpsGatewayServerMetrics = {
    connectionsOpened: 0,
    handshakesAccepted: 0,
    handshakesRejected: 0,
    packetsDecoded: 0,
    packetsRejected: 0,
    reportsIngestedLive: 0,
    reportsBuffered: 0,
  };

  private readonly ingestClient: GpsGatewayIngestClientLike;
  private readonly buffer: DurableTelemetryBuffer;
  private readonly log: (line: string) => void;
  private readonly idleTimeoutMs: number;
  // ATW-246 finding 2: IMEIs with a currently-open, handshake-accepted connection on
  // this process. A single always-on gateway process (this package's own header/README)
  // makes in-process state a complete fix -- see this file's own header for why a
  // Postgres advisory lock would NOT be reliable given this gateway's stateless
  // per-RPC-call architecture (src/ingestClient.ts).
  private readonly activeImeis = new Set<string>();

  constructor(options: GpsGatewayServerOptions) {
    this.ingestClient = options.ingestClient;
    this.buffer = options.buffer;
    this.log = options.onLog ?? (() => {});
    this.idleTimeoutMs = options.idleTimeoutMs ?? DEFAULT_IDLE_TIMEOUT_MS;
    this.server = createServer((socket) => this.handleConnection(socket));
    // ATW-246 finding 6: Node destroys a connection beyond this cap before its own
    // 'connection' handler even runs -- see node:net's own documented maxConnections
    // semantics.
    this.server.maxConnections = options.maxConnections ?? DEFAULT_MAX_CONNECTIONS;
  }

  listen(port: number, host: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(port, host, () => {
        this.server.removeListener("error", reject);
        resolve();
      });
    });
  }

  /** The actual bound TCP port -- useful when listen() was called with port 0 (an OS-assigned ephemeral port, this package's own test suite's own pattern for a collision-free port per test). */
  get boundPort(): number {
    const address = this.server.address();
    if (typeof address !== "object" || address === null) {
      throw new Error("server_not_listening: boundPort read before listen() resolved");
    }
    return address.port;
  }

  close(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server.close((error) => (error ? reject(error) : resolve()));
    });
  }

  private handleConnection(socket: Socket): void {
    this.metrics.connectionsOpened += 1;
    // ATW-030: shared by reference with every drainAccumulator() call on this connection
    // -- never snapshotted-and-committed, which silently dropped bytes that arrived mid-
    // ingest. See ConnectionBuffers' own doc comment.
    const conn: ConnectionBuffers = { accumulator: Buffer.alloc(0), state: { phase: "awaiting_handshake" } };
    let closed = false;
    // ATW-246 finding 2: the exact IMEI (if any) this connection registered into
    // `activeImeis`, so it can be released on close regardless of how the connection
    // ends (graceful, error, timeout, oversized/malformed packet). Tracked separately
    // from `state` (which is only committed back to this outer scope once drainAccumulator
    // returns) so a socket that closes mid-drain still reliably releases its own IMEI --
    // never a stuck "already active" entry outliving its own connection.
    let registeredImei: string | null = null;
    // Serializes 'data' event processing -- Node can fire another 'data' event before
    // an async drainAccumulator() call for the previous chunk has finished awaiting an
    // RPC round-trip; without this chain, two overlapping drains would each capture a
    // stale accumulator/state snapshot and corrupt/duplicate the byte stream.
    let processingChain: Promise<void> = Promise.resolve();

    const closeWithLog = (reason: string) => {
      if (closed) {
        return;
      }
      closed = true;
      this.log(`connection closed: ${reason}`);
      socket.destroy();
    };

    // ATW-246 finding 6: an idle connection (no bytes at all within idleTimeoutMs) is
    // closed by the server rather than held open indefinitely -- socket.setTimeout does
    // not itself close the socket, it only emits 'timeout'; destroying it here is what
    // actually bounds the resource. Node resets this timer on every 'data' event on its
    // own, so a genuinely active device is never at risk of tripping it.
    socket.setTimeout(this.idleTimeoutMs, () => closeWithLog("idle_timeout"));

    // ATW-246 finding 2: always runs on close, regardless of path (graceful end, error,
    // destroy, idle timeout, oversized/malformed packet) -- Node's net.Socket guarantees
    // a 'close' event fires exactly once after full teardown, making this the one
    // reliable place to release this connection's own IMEI claim.
    socket.on("close", () => {
      if (registeredImei !== null) {
        this.activeImeis.delete(registeredImei);
        registeredImei = null;
      }
    });

    socket.on("data", (chunk: Bytes) => {
      if (closed) {
        return;
      }
      conn.accumulator = Buffer.concat([conn.accumulator, chunk]);

      if (conn.accumulator.length > MAX_BUFFERED_BYTES) {
        this.metrics.packetsRejected += 1;
        closeWithLog("oversized_packet");
        return;
      }

      processingChain = processingChain
        .then(() => {
          if (closed) {
            return;
          }
          return this.drainAccumulator(
            socket,
            conn,
            closeWithLog,
            (imei) => {
              // ATW-246 finding 2: registers the IMEI as active at the exact synchronous
              // instant the handshake is accepted -- returns false if another connection
              // already holds it, in which case the caller rejects this handshake instead.
              if (this.activeImeis.has(imei)) {
                return false;
              }
              this.activeImeis.add(imei);
              registeredImei = imei;
              return true;
            },
          );
        })
        .catch((error: Error) => {
          // Guards against an unhandled rejection AND against the chain staying
          // permanently rejected (which would silently stop processing every
          // subsequent chunk on this connection) -- any error reaching here is one
          // drainAccumulator's own try/catch blocks did not already convert into a
          // clean closeWithLog() call (e.g. a filesystem error from the durable
          // buffer), so it is itself a reason to close the connection.
          closeWithLog(`unexpected_processing_error: ${error.message}`);
        });
    });

    socket.on("error", (error) => {
      this.log(`socket error: ${error.message}`);
    });
  }

  private async drainAccumulator(
    socket: Socket,
    conn: ConnectionBuffers,
    closeWithLog: (reason: string) => void,
    tryRegisterActiveImei: (imei: string) => boolean,
  ): Promise<void> {
    // ATW-030: `conn` is read fresh at the top of every iteration and every consumed
    // prefix is removed from it BEFORE the following await, so a chunk appended by the
    // 'data' handler while an ingest/handshake round-trip is in flight is preserved and
    // decoded on the next pass instead of being overwritten by a stale snapshot.
    for (;;) {
      if (conn.state.phase === "awaiting_handshake") {
        let handshake;
        try {
          handshake = decodeImeiHandshake(conn.accumulator);
        } catch (error) {
          this.metrics.handshakesRejected += 1;
          closeWithLog(`malformed_handshake: ${(error as Error).message}`);
          return;
        }
        if (!handshake) {
          return;
        }
        conn.accumulator = conn.accumulator.subarray(handshake.bytesConsumed);

        let result;
        try {
          result = await this.ingestClient.resolveHandshake(handshake.imei);
        } catch (error) {
          this.metrics.handshakesRejected += 1;
          socket.write(encodeHandshakeResponse(false));
          closeWithLog(`handshake_authentication_failed: ${(error as Error).message}`);
          return;
        }

        if (!result.accepted || !result.deviceId) {
          this.metrics.handshakesRejected += 1;
          socket.write(encodeHandshakeResponse(false));
          closeWithLog(`handshake_rejected: ${result.rejectionReason ?? "unknown"}`);
          return;
        }

        // ATW-246 finding 2: reject a second concurrent handshake for an IMEI that
        // already has an active, open connection on this process -- checked only after
        // the real device/tenant resolution above succeeds, so an unknown/foreign IMEI
        // still gets its own ordinary handshake_rejected outcome, never this one.
        if (!tryRegisterActiveImei(handshake.imei)) {
          this.metrics.handshakesRejected += 1;
          socket.write(encodeHandshakeResponse(false));
          closeWithLog("handshake_rejected: imei_already_connected");
          return;
        }

        this.metrics.handshakesAccepted += 1;
        socket.write(encodeHandshakeResponse(true));
        conn.state = { phase: "awaiting_avl_data", deviceId: result.deviceId, imei: handshake.imei };
        continue;
      }

      // awaiting_avl_data
      let decoded;
      try {
        decoded = decodeAvlDataPacket(conn.accumulator);
      } catch (error) {
        this.metrics.packetsRejected += 1;
        closeWithLog(`malformed_avl_packet: ${(error as Error).message}`);
        return;
      }
      if (!decoded) {
        return;
      }
      const deviceId = conn.state.deviceId;
      conn.accumulator = conn.accumulator.subarray(decoded.bytesConsumed);
      this.metrics.packetsDecoded += 1;

      const reports = decoded.packet.records.map(recordToReport);
      try {
        await this.ingestClient.ingestBatch(deviceId, reports);
        this.metrics.reportsIngestedLive += reports.length;
      } catch (error) {
        this.log(`live ingest failed, buffering durably: ${(error as Error).message}`);
        await this.buffer.enqueue({ deviceId, reports, enqueuedAt: new Date().toISOString() });
        this.metrics.reportsBuffered += reports.length;
      }

      socket.write(encodeAckResponse(decoded.packet.records.length));
    }
  }
}
