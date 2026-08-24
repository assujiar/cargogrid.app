/**
 * GET /api/health (HDN-382, Observability Audit). Liveness probe -- no dependency
 * check, per docs/standards/OBSERVABILITY_STANDARDS.md §7's own already-fixed contract:
 * "returns {status: 'ok'} with no dependency check." Proves only that the Next.js
 * process itself is up and serving requests; use /api/ready to also prove the database
 * is reachable. Unauthenticated by design (a load balancer/orchestrator's own liveness
 * probe cannot present a session) -- returns no tenant or application data of any kind.
 */

export async function GET(): Promise<Response> {
  return Response.json({ status: "ok" }, { status: 200 });
}
