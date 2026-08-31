/**
 * Public status-page probe interpretation (ISS-2026-304).
 *
 * WHAT THIS CAN AND CANNOT TELL A VISITOR, decided here rather than left implicit
 *
 *   `ISS-2026-304` correctly refused to build a status page hosted inside the system it
 *   reports on, because such a page "is useless during exactly the outage it exists to
 *   report". That argument holds for the case it was made about — the whole deployment being
 *   down — and it does not hold for the outage class this product is actually most exposed
 *   to.
 *
 *   `ISS-2026-261` records that CargoGrid runs on exactly one managed backend vendor with no
 *   failover path. A Supabase outage is the realistic incident, and it does not take the
 *   front end with it: the status page is statically rendered and served from the CDN, so it
 *   loads and answers correctly while the database is unreachable. That is the case worth
 *   covering, and it is covered.
 *
 *   The case it genuinely cannot cover is the host itself being down — then the visitor never
 *   receives this page at all. The page says so in its own words rather than implying a
 *   completeness it does not have, and the residual (a status page on independent
 *   infrastructure) stays owner-owned, because it is an account and a hosting decision.
 *
 * WHY THE INTERPRETATION LIVES HERE
 *
 *   Two probes with three outcomes each produce more combinations than they look like, and
 *   the interesting ones are the disagreements — a liveness probe that answers while the
 *   readiness probe fails is the exact shape of a backend outage, and it must never be
 *   rendered as "operational". Putting that decision in a pure function means it is tested
 *   without a browser, a server, or a live backend.
 */

/** What a single probe endpoint told us. `unreachable` covers a network failure, a timeout, and any non-JSON response — from a visitor's point of view they are the same thing. */
export type ProbeOutcome = "ok" | "degraded" | "unreachable";

export type ServiceState = "operational" | "degraded" | "down" | "unknown";

export interface ServiceStatus {
  readonly state: ServiceState;
  /** One sentence a non-technical visitor can act on. */
  readonly headline: string;
  readonly detail: string;
}

/**
 * Combine the liveness probe (`/api/health`, no dependency check) and the readiness probe
 * (`/api/ready`, which also proves the database is reachable) into one answer.
 *
 * The asymmetry is deliberate: readiness failing while liveness succeeds is a real, specific
 * and common state — the application is serving, the database is not — and collapsing it into
 * a generic "down" would tell an operator the opposite of what is happening.
 */
export function interpretServiceStatus(liveness: ProbeOutcome, readiness: ProbeOutcome): ServiceStatus {
  if (liveness === "unreachable") {
    // Liveness needs no backend at all, so failing it means the application itself is not
    // answering. Note this page still loaded, which is the point of serving it statically.
    return {
      state: "down",
      headline: "CargoGrid is not responding",
      detail:
        "The application is not answering requests. This page is served separately from the application, which is why you can still read it. If this persists, contact your CargoGrid administrator.",
    };
  }

  if (readiness === "unreachable" || readiness === "degraded") {
    return {
      state: "degraded",
      headline: "CargoGrid is up, but its database is unreachable",
      detail:
        "The application is running and answering requests, but it cannot reach the database behind it. Signing in and loading data will fail or be very slow. Work already saved is not affected by this.",
    };
  }

  if (liveness === "degraded") {
    // The liveness probe has no degraded branch today. If one is ever added, saying "unknown"
    // is the honest answer rather than guessing which way it leans.
    return {
      state: "unknown",
      headline: "CargoGrid's status could not be determined",
      detail: "The application reported a state this page does not recognise. Treat it as unverified rather than healthy.",
    };
  }

  return {
    state: "operational",
    headline: "All CargoGrid systems are operational",
    detail: "The application is answering requests and its database is reachable.",
  };
}

/**
 * Turn one probe response into an outcome.
 *
 * Any non-2xx that still carries `status: "degraded"` is reported as degraded rather than
 * unreachable — `/api/ready` answers 503 with exactly that body, and a 503 that arrived is
 * meaningfully different from a request that never got an answer.
 */
export function readProbeResponse(httpStatus: number, body: unknown): ProbeOutcome {
  const status = typeof body === "object" && body !== null ? (body as { status?: unknown }).status : undefined;
  if (status === "degraded") return "degraded";
  if (httpStatus >= 200 && httpStatus < 300 && status === "ok") return "ok";
  return "unreachable";
}
