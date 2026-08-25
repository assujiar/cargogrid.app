/**
 * Third-party GPS platform webhook ingestion endpoint (ATW-226E, CG-S10-ATW-006's
 * family, Prompt 226 decomposition child). The second real HTTP API route this
 * repository builds, after `app/api/tracking/driver-mobile/route.ts` (ATW-226C).
 *
 * `connectionId` (not `provider_code`) is the routable identity -- each tenant's own
 * connection to a provider gets its own webhook URL, the natural way HTTP (unlike
 * ATW-226D's raw-TCP IMEI-only handshake) lets a per-tenant credential be looked up
 * directly rather than resolved globally (see the migration's own header design note 1).
 *
 * The raw request body is read as text, never re-serialized through `JSON.parse`/
 * `JSON.stringify`, before being handed to `ingestThirdPartyProviderWebhookEvent` --
 * HMAC-SHA256 signature verification (ADR-0011) is computed over the exact bytes the
 * provider sent; re-serializing first (even semantically-equivalent JSON) can reorder
 * keys or change whitespace and silently break every legitimate signature.
 *
 * No Supabase Auth session exists for a third-party provider caller -- authorization is
 * entirely the HMAC signature `app.verify_third_party_provider_webhook_signature`
 * itself validates. This route uses the service-role client exactly as
 * `app/api/tracking/driver-mobile/route.ts` (ATW-226C) already does for the identical
 * reason -- the service-role credential itself never reaches the provider or the
 * browser.
 */

import { createHash } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { ingestThirdPartyProviderWebhookEvent } from "../../../../../server/mutations/third-party-provider-adapter.ts";

const STATUS_BY_INGEST_STATUS: Record<string, number> = {
  ok: 200,
  duplicate: 200,
  quarantined: 200,
  invalid: 401,
  rate_limited: 429,
};

export async function POST(request: Request, { params }: { params: Promise<{ connectionId: string }> }): Promise<Response> {
  const { connectionId } = await params;

  const rawPayload = await request.text();

  const timestampHeader = request.headers.get("x-webhook-timestamp");
  const signature = request.headers.get("x-webhook-signature");
  const timestamp = timestampHeader === null ? Number.NaN : Number(timestampHeader);

  if (!signature || !Number.isFinite(timestamp) || rawPayload.length === 0) {
    return Response.json({ ingestStatus: "invalid" }, { status: 400 });
  }

  // client_key is a sha256 hash of the caller's own best-effort IP address -- never the
  // raw IP itself -- the identical disclosed convention
  // app/api/tracking/driver-mobile/route.ts (ATW-226C) already established, since
  // app.third_party_provider_ingestion_attempts is retained as rate-limit evidence.
  const ipAddress = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const clientKey = createHash("sha256").update(ipAddress).digest("hex");

  const client = createSupabaseServiceRoleClient();
  // RGL-402: connectionId is unvalidated, attacker-controlled URL-path text -- a
  // non-UUID value (malformed, injection-shaped, or a path-traversal attempt) fails
  // ingestThirdPartyProviderWebhookEvent's own internal Zod .uuid() parse, which
  // throws rather than returning an ingestStatus. Uncaught, that surfaced as a raw
  // 500 instead of this route's own documented "never throws" contract (see this
  // file's header comment) -- live-forced against production.
  try {
    const result = await ingestThirdPartyProviderWebhookEvent(client, {
      connectionId,
      clientKey,
      rawPayload,
      timestamp,
      signature,
    });
    return Response.json({ ingestStatus: result.ingestStatus, reportId: result.reportId }, { status: STATUS_BY_INGEST_STATUS[result.ingestStatus] ?? 200 });
  } catch {
    return Response.json({ ingestStatus: "invalid" }, { status: 400 });
  }
}
