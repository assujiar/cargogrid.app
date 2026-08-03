/**
 * Driver Mobile GPS HTTPS ingestion endpoint (ATW-226C, CG-S10-ATW-006's family, Prompt
 * 226 decomposition child). The first real HTTP API route this repository builds
 * (every prior capability's own "no REST/GraphQL surface exists yet" disclosure does
 * not apply to this one route -- it is a webhook-shaped ingestion endpoint, not a
 * REST/GraphQL resource API, the same distinction OPS-180's own public tracking *page*
 * (a Server Component RPC call, not a route) already drew for a different reason).
 *
 * No Supabase Auth session exists for a Driver PWA caller -- authorization is entirely
 * the bearer token app.ingest_driver_mobile_report itself validates (see that
 * function's own migration header). This route never inspects cookies and never uses
 * an authenticated/RLS-scoped client; it uses the service-role client exactly the way
 * `app/(public)/tracking/[token]/page.tsx` (OPS-180) already does for the same reason
 * (no session exists to be RLS-scoped against), then leans entirely on the RPC's own
 * SECURITY DEFINER + rate-limit + token-hash gate for safety -- the service-role
 * credential itself never reaches the browser.
 */

import { createHash } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import { ingestDriverMobileReport } from "../../../../server/mutations/driver-mobile-tracking.ts";
import { IngestDriverMobileReportInputSchema } from "../../../../server/contracts/driver-mobile-tracking/driver-mobile-tracking.ts";

const STATUS_BY_INGEST_STATUS: Record<string, number> = {
  ok: 200,
  invalid: 401,
  rate_limited: 429,
};

export async function POST(request: Request): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ ingestStatus: "invalid" }, { status: 400 });
  }

  const authorizationHeader = request.headers.get("authorization") ?? "";
  const bearerToken = authorizationHeader.startsWith("Bearer ") ? authorizationHeader.slice("Bearer ".length) : null;

  // client_key is a sha256 hash of the caller's own best-effort IP address -- never the
  // raw IP itself -- the identical disclosed convention
  // app/(public)/tracking/[token]/page.tsx (OPS-180) already established, since
  // app.driver_mobile_ingestion_attempts is retained as rate-limit evidence.
  const ipAddress = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const clientKey = createHash("sha256").update(ipAddress).digest("hex");

  const parsedInput = IngestDriverMobileReportInputSchema.safeParse({
    ...(typeof body === "object" && body !== null ? body : {}),
    rawToken: bearerToken ?? (typeof body === "object" && body !== null ? (body as Record<string, unknown>).rawToken : undefined),
    clientKey,
  });
  if (!parsedInput.success) {
    return Response.json({ ingestStatus: "invalid" }, { status: 400 });
  }

  const client = createSupabaseServiceRoleClient();
  const result = await ingestDriverMobileReport(client, parsedInput.data);

  return Response.json(
    { ingestStatus: result.ingestStatus, reportId: result.reportId, sessionEnded: result.sessionEnded },
    { status: STATUS_BY_INGEST_STATUS[result.ingestStatus] ?? 200 },
  );
}
