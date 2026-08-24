/**
 * GET /api/ready (HDN-382, Observability Audit). Readiness probe -- additionally checks
 * database connectivity, per docs/standards/OBSERVABILITY_STANDARDS.md §7's own
 * already-fixed contract: "additionally checks DB connectivity and returns 503 with
 * {status: 'degraded', reason: [...]} on failure -- never a false 'ok'." Calls the
 * trivial, side-effect-free app.ping() RPC (supabase/migrations/
 * 20260816000000_harden_observability_audit_findings.sql) via the service-role client --
 * no session/tenant context is needed or used, and the probe touches no application
 * table, so no tenant data can leak through this route. Unauthenticated by design (an
 * orchestrator's own readiness probe cannot present a session).
 */

import { createSupabaseServiceRoleClient } from "../../../lib/supabase/service-role.ts";

export async function GET(): Promise<Response> {
  try {
    const client = createSupabaseServiceRoleClient();
    const { error } = await client.rpc("ping");
    if (error) {
      return Response.json({ status: "degraded", reason: ["database_unreachable"] }, { status: 503 });
    }
    return Response.json({ status: "ok" }, { status: 200 });
  } catch {
    return Response.json({ status: "degraded", reason: ["database_unreachable"] }, { status: 503 });
  }
}
