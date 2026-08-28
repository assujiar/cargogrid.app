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
 *
 * ISS-2026-253 fix: the client-visible response shape is unchanged (still a
 * bare 503 {status:"degraded", reason:["database_unreachable"]} on every
 * failure branch -- no secret or stack-trace text is ever returned to the
 * caller) but every failure branch now also emits one structured, server-side
 * log event via this repository's own scripts/observability/logger.ts
 * foundation, distinguishing 3 failure shapes an on-call responder otherwise
 * cannot tell apart from the HTTP response alone: (1) the RPC itself returned
 * a Postgres/PostgREST error (a genuine DB-reachability problem), (2) client
 * construction threw because a required env var is unset (a deploy/config
 * defect, not a DB outage -- only the env var NAME is logged, never a
 * secret value), (3) any other exception. This is this codebase's first real
 * caller of scripts/observability/logger.ts's log() -- the module existed
 * only as a tested-but-unused foundation before this fix (ISS-2026-252).
 */

import { createSupabaseServiceRoleClient } from "../../../lib/supabase/service-role.ts";
import { log, generateCorrelationId } from "../../../scripts/observability/logger.ts";

const MISSING_ENV_VAR_PATTERN = /is not set -- see \.env\.example$/;

export async function GET(): Promise<Response> {
  const correlationId = generateCorrelationId();
  try {
    const client = createSupabaseServiceRoleClient();
    const { error } = await client.rpc("ping");
    if (error) {
      log({
        severity: "error",
        event: "ready_check_db_unreachable",
        message: "GET /api/ready: app.ping() RPC returned an error -- treating readiness as degraded (database_unreachable).",
        correlationId,
        source: "api",
        fields: {
          rpc_error_message: error.message,
          rpc_error_code: error.code ?? null,
        },
      });
      return Response.json({ status: "degraded", reason: ["database_unreachable"] }, { status: 503 });
    }
    return Response.json({ status: "ok" }, { status: 200 });
  } catch (caught) {
    const message = caught instanceof Error ? caught.message : String(caught);
    const isMissingEnvVar = MISSING_ENV_VAR_PATTERN.test(message);
    log({
      severity: isMissingEnvVar ? "critical" : "error",
      event: isMissingEnvVar ? "ready_check_missing_env_var" : "ready_check_unexpected_exception",
      message: isMissingEnvVar
        ? "GET /api/ready: service-role client construction threw because a required env var is unset -- this is a deploy/config defect, not a genuine database outage, even though the HTTP response is identical to one."
        : "GET /api/ready: an unexpected exception was thrown while checking database connectivity.",
      correlationId,
      source: "api",
      fields: {
        error_name: caught instanceof Error ? caught.name : "unknown",
        // Safe to log verbatim: requireEnv()'s own thrown message names only the
        // unset env var (e.g. "SUPABASE_SERVICE_ROLE_KEY is not set -- see
        // .env.example") -- never the secret value itself. Any other caught
        // exception's message is logged as-is too, matching this repository's
        // established "message is a caller-discipline surface, not
        // auto-redacted" convention (scripts/observability/logger.ts's own
        // redact() doc comment) -- this route touches no tenant data and no
        // secret value before this point, so there is nothing sensitive for a
        // message here to contain.
        error_message: message,
      },
    });
    return Response.json({ status: "degraded", reason: ["database_unreachable"] }, { status: 503 });
  }
}
