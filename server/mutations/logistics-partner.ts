/**
 * Carrier, Port, Airport and Customs Integrations mutation primitives
 * (IAE-016, Prompt 344). Thin, typed wrappers around
 * app.ingest_logistics_partner_webhook_event /
 * app.trigger_logistics_partner_poll_sync /
 * app.record_logistics_partner_sync_event / app.review_logistics_partner_event
 * (supabase/migrations/20260805030000_create_intelligence_carrier_port_airport_customs_integrations.sql).
 */

import {
  IngestLogisticsPartnerWebhookEventInputSchema,
  parseIngestLogisticsPartnerWebhookEventResult,
  TriggerLogisticsPartnerPollSyncInputSchema,
  RecordLogisticsPartnerSyncEventInputSchema,
  ReviewLogisticsPartnerEventInputSchema,
  parseLogisticsPartnerEvent,
  type IngestLogisticsPartnerWebhookEventInput,
  type IngestLogisticsPartnerWebhookEventResult,
  type TriggerLogisticsPartnerPollSyncInput,
  type RecordLogisticsPartnerSyncEventInput,
  type ReviewLogisticsPartnerEventInput,
  type LogisticsPartnerEvent,
} from "../contracts/logistics-partner/logistics-partner.ts";

export interface LogisticsPartnerMutationRpcClient {
  rpc(
    fn: "ingest_logistics_partner_webhook_event" | "trigger_logistics_partner_poll_sync" | "record_logistics_partner_sync_event" | "review_logistics_partner_event",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const LOGISTICS_PARTNER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "logistics_partner_client_key_required",
  "logistics_partner_invalid_adapter_code",
  "logistics_partner_connection_not_found",
  "logistics_partner_connection_not_active",
  "logistics_partner_event_not_found",
  "logistics_partner_event_invalid_decision",
  "logistics_partner_event_invalid_type",
  "logistics_partner_event_unsafe_payload",
  "logistics_partner_event_invalid_limit",
] as const;
type KnownLogisticsPartnerMutationErrorCode = (typeof LOGISTICS_PARTNER_KNOWN_MUTATION_ERROR_CODES)[number];
export type LogisticsPartnerMutationErrorCode = KnownLogisticsPartnerMutationErrorCode | "mutation_failed" | "invalid_response";

export class LogisticsPartnerMutationError extends Error {
  readonly code: LogisticsPartnerMutationErrorCode;

  constructor(code: LogisticsPartnerMutationErrorCode, message: string) {
    super(message);
    this.name = "LogisticsPartnerMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LogisticsPartnerMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (LOGISTICS_PARTNER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownLogisticsPartnerMutationErrorCode) : "mutation_failed";
}

/** The provider's own webhook entry point. Never throws for a bad signature/malformed payload/duplicate event -- see the migration's own header. Only a genuine transport/serialization error throws. */
export async function ingestLogisticsPartnerWebhookEvent(client: LogisticsPartnerMutationRpcClient, input: IngestLogisticsPartnerWebhookEventInput): Promise<IngestLogisticsPartnerWebhookEventResult> {
  const parsedInput = IngestLogisticsPartnerWebhookEventInputSchema.parse(input);
  const { data, error } = await client.rpc("ingest_logistics_partner_webhook_event", {
    p_connection_id: parsedInput.connectionId,
    p_client_key: parsedInput.clientKey,
    p_raw_payload: parsedInput.rawPayload,
    p_timestamp: parsedInput.timestamp,
    p_signature: parsedInput.signature,
  });
  if (error) {
    throw new LogisticsPartnerMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LogisticsPartnerMutationError("invalid_response", "ingest_logistics_partner_webhook_event returned no row");
  }
  return parseIngestLogisticsPartnerWebhookEventResult(row as Record<string, unknown>);
}

export interface TriggerLogisticsPartnerPollSyncResult {
  readonly jobId: string;
}

/** The real first caller of app.check_integration_connection_active (IAE-336). */
export async function triggerLogisticsPartnerPollSync(client: LogisticsPartnerMutationRpcClient, input: TriggerLogisticsPartnerPollSyncInput): Promise<TriggerLogisticsPartnerPollSyncResult> {
  const parsedInput = TriggerLogisticsPartnerPollSyncInputSchema.parse(input);
  const { data, error } = await client.rpc("trigger_logistics_partner_poll_sync", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LogisticsPartnerMutationError(classifyError(error.message), error.message);
  }
  const row = data as Record<string, unknown> | null;
  if (!row || typeof row.job_id !== "string") {
    throw new LogisticsPartnerMutationError("invalid_response", "trigger_logistics_partner_poll_sync returned no row");
  }
  return { jobId: row.job_id };
}

/** The real poll worker's own bounded write -- atomic insert-on-conflict-do-nothing-returning, so a duplicate provider_event_id within one poll batch is never a race. */
export async function recordLogisticsPartnerSyncEvent(client: LogisticsPartnerMutationRpcClient, input: RecordLogisticsPartnerSyncEventInput): Promise<LogisticsPartnerEvent> {
  const parsedInput = RecordLogisticsPartnerSyncEventInputSchema.parse(input);
  const { data, error } = await client.rpc("record_logistics_partner_sync_event", {
    p_tenant_id: parsedInput.tenantId,
    p_connection_id: parsedInput.connectionId,
    p_provider_event_id: parsedInput.providerEventId,
    p_event_type: parsedInput.eventType,
    p_external_reference: parsedInput.externalReference,
    p_raw_payload: parsedInput.rawPayload,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LogisticsPartnerMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new LogisticsPartnerMutationError("invalid_response", "record_logistics_partner_sync_event returned no row");
  }
  return parseLogisticsPartnerEvent(data as Record<string, unknown>);
}

/** Evidence-only -- never writes to app.shipment_orders. Authority: OPS:Edit for the event's own tenant. */
export async function reviewLogisticsPartnerEvent(client: LogisticsPartnerMutationRpcClient, input: ReviewLogisticsPartnerEventInput): Promise<LogisticsPartnerEvent> {
  const parsedInput = ReviewLogisticsPartnerEventInputSchema.parse(input);
  const { data, error } = await client.rpc("review_logistics_partner_event", {
    p_event_id: parsedInput.eventId,
    p_decision: parsedInput.decision,
    p_notes: parsedInput.notes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LogisticsPartnerMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new LogisticsPartnerMutationError("invalid_response", "review_logistics_partner_event returned no row");
  }
  return parseLogisticsPartnerEvent(data as Record<string, unknown>);
}
