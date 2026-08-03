/**
 * Health/readiness/metrics HTTP endpoints (226_GPS_TELEMATICS_INTEGRATION_PROMPT.md
 * §14B: "health/readiness/metrics"). A tiny, dependency-free node:http server --
 * deliberately not the Next.js app's own API route surface, since this package is
 * independently deployed and must expose its own liveness/readiness signal to whatever
 * always-on container/VPS platform ends up hosting it (220_*.md §6, deferred hosting
 * ADR).
 */

import { createServer, type Server } from "node:http";
import type { GpsGatewayServerMetrics } from "./server.ts";

export interface HealthServerOptions {
  getMetrics: () => GpsGatewayServerMetrics;
  getReady: () => boolean;
}

export class HealthServer {
  private readonly server: Server;

  constructor(options: HealthServerOptions) {
    this.server = createServer((req, res) => {
      if (req.url === "/healthz") {
        res.writeHead(200, { "content-type": "text/plain" });
        res.end("ok");
        return;
      }
      if (req.url === "/readyz") {
        const ready = options.getReady();
        res.writeHead(ready ? 200 : 503, { "content-type": "text/plain" });
        res.end(ready ? "ready" : "not_ready");
        return;
      }
      if (req.url === "/metrics") {
        const metrics = options.getMetrics();
        const lines = Object.entries(metrics).map(([key, value]) => `gps_gateway_${key} ${value}`);
        res.writeHead(200, { "content-type": "text/plain" });
        res.end(lines.join("\n") + "\n");
        return;
      }
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not_found");
    });
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

  close(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}
