/**
 * Payment gateway webhook ingestion endpoint (IAE-017, Prompt 345). Mirrors
 * app/api/webhooks/logistics-partner/[connectionId]/route.ts (IAE-016)
 * exactly in shape, which itself mirrors the original GPS receiver
 * (ATW-226E).
 *
 * The raw request body is read as text, never re-serialized through
 * `JSON.parse`/`JSON.stringify`, before being handed to
 * ingestFinancePaymentGatewayWebhookEvent -- HMAC-SHA256 signature
 * verification (ADR-0011) is computed over the exact bytes the provider
 * sent.
 *
 * No Supabase Auth session exists for a payment-gateway caller --
 * authorization is entirely the HMAC signature
 * app.verify_finance_payment_webhook_signature itself validates. The
 * service-role client is used for the same reason every prior webhook
 * receiver in this repository already established -- the service-role
 * credential itself never reaches the provider or the browser.
 */

import { createHash } from "node:crypto";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { ingestFinancePaymentGatewayWebhookEvent, type FinanceIntegrationsMutationRpcClient } from "../../../../../server/mutations/bank-payment-tax-integrations.ts";

const STATUS_BY_INGEST_STATUS: Record<string, number> = {
  ok: 200,
  duplicate: 200,
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

  // client_key is a sha256 hash of the caller's own best-effort IP address --
  // never the raw IP itself -- the identical disclosed convention every
  // prior webhook receiver already established, since
  // app.finance_payment_gateway_ingestion_attempts is retained as
  // rate-limit evidence.
  const ipAddress = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const clientKey = createHash("sha256").update(ipAddress).digest("hex");

  const client = createSupabaseServiceRoleClient() as unknown as FinanceIntegrationsMutationRpcClient;
  // RGL-402: connectionId is unvalidated, attacker-controlled URL-path text -- a
  // non-UUID value fails ingestFinancePaymentGatewayWebhookEvent's own internal Zod
  // .uuid() parse, which throws rather than returning an ingestStatus. Uncaught,
  // that surfaced as a raw 500 instead of a clean 400 -- live-forced against the
  // identical sibling route (third-party-gps), the same bug class.
  try {
    const result = await ingestFinancePaymentGatewayWebhookEvent(client, {
      connectionId,
      clientKey,
      rawPayload,
      timestamp,
      signature,
    });
    return Response.json({ ingestStatus: result.ingestStatus, eventId: result.eventId }, { status: STATUS_BY_INGEST_STATUS[result.ingestStatus] ?? 200 });
  } catch {
    return Response.json({ ingestStatus: "invalid" }, { status: 400 });
  }
}
