/**
 * Third-party GPS platform adapter mutation primitives (ATW-226E). Thin, typed wrappers
 * around app.register_third_party_provider_connection / app.rotate_third_party_provider_
 * webhook_secret / app.update_third_party_provider_poll_cursor (dispatcher/administration-
 * facing, authenticated/service_role) and app.ingest_third_party_provider_webhook_event
 * (the one anon-callable RPC in this capability -- see
 * supabase/migrations/20260729380000_create_advanced_tms_third_party_provider_adapter.sql's
 * own header design note 2 for why this is safe).
 *
 * app.ingest_third_party_provider_webhook_event never raises for an auth/validation/
 * business-outcome failure -- every outcome is a returned ingestStatus, so
 * ingestThirdPartyProviderWebhookEvent below never throws for a bad signature/unmapped
 * vehicle/duplicate event either, the identical shape
 * server/mutations/driver-mobile-tracking.ts's own ingestDriverMobileReport already
 * established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RegisterThirdPartyProviderConnectionInputSchema,
  RotateThirdPartyProviderWebhookSecretInputSchema,
  UpdateThirdPartyProviderPollCursorInputSchema,
  IngestThirdPartyProviderWebhookEventInputSchema,
  parseRegisterThirdPartyProviderConnectionResult,
  parseRotateThirdPartyProviderWebhookSecretResult,
  parseThirdPartyProviderConnection,
  parseIngestThirdPartyProviderWebhookEventResult,
  type RegisterThirdPartyProviderConnectionInput,
  type RotateThirdPartyProviderWebhookSecretInput,
  type UpdateThirdPartyProviderPollCursorInput,
  type IngestThirdPartyProviderWebhookEventInput,
  type RegisterThirdPartyProviderConnectionResult,
  type RotateThirdPartyProviderWebhookSecretResult,
  type ThirdPartyProviderConnection,
  type IngestThirdPartyProviderWebhookEventResult,
} from "../contracts/third-party-provider-adapter/third-party-provider-adapter.ts";

export type ThirdPartyProviderAdapterMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const THIRD_PARTY_PROVIDER_ADAPTER_KNOWN_MUTATION_ERROR_CODES = [
  "provider_code_required",
  "invalid_integration_mode",
  "insufficient_authority",
  "connection_not_found",
  "not_a_webhook_connection",
  "not_a_poll_connection",
] as const;
type KnownThirdPartyProviderAdapterMutationErrorCode = (typeof THIRD_PARTY_PROVIDER_ADAPTER_KNOWN_MUTATION_ERROR_CODES)[number];
export type ThirdPartyProviderAdapterMutationErrorCode = KnownThirdPartyProviderAdapterMutationErrorCode | "mutation_failed" | "invalid_response";

export class ThirdPartyProviderAdapterMutationError extends Error {
  readonly code: ThirdPartyProviderAdapterMutationErrorCode;

  constructor(code: ThirdPartyProviderAdapterMutationErrorCode, message: string) {
    super(message);
    this.name = "ThirdPartyProviderAdapterMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ThirdPartyProviderAdapterMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (THIRD_PARTY_PROVIDER_ADAPTER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownThirdPartyProviderAdapterMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent on (tenant, provider_code). Returns the raw webhook secret exactly once, only on first creation. */
export async function registerThirdPartyProviderConnection(
  client: ThirdPartyProviderAdapterMutationRpcClient,
  input: RegisterThirdPartyProviderConnectionInput,
): Promise<RegisterThirdPartyProviderConnectionResult> {
  const parsedInput = RegisterThirdPartyProviderConnectionInputSchema.parse(input);
  const { data, error } = await client.rpc("register_third_party_provider_connection", {
    p_tenant_id: parsedInput.tenantId,
    p_provider_code: parsedInput.providerCode,
    p_integration_mode: parsedInput.integrationMode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ThirdPartyProviderAdapterMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ThirdPartyProviderAdapterMutationError("invalid_response", "register_third_party_provider_connection returned no row");
  }
  return parseRegisterThirdPartyProviderConnectionResult(row as Record<string, unknown>);
}

export async function rotateThirdPartyProviderWebhookSecret(
  client: ThirdPartyProviderAdapterMutationRpcClient,
  input: RotateThirdPartyProviderWebhookSecretInput,
): Promise<RotateThirdPartyProviderWebhookSecretResult> {
  const parsedInput = RotateThirdPartyProviderWebhookSecretInputSchema.parse(input);
  const { data, error } = await client.rpc("rotate_third_party_provider_webhook_secret", {
    p_connection_id: parsedInput.connectionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ThirdPartyProviderAdapterMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ThirdPartyProviderAdapterMutationError("invalid_response", "rotate_third_party_provider_webhook_secret returned no row");
  }
  return parseRotateThirdPartyProviderWebhookSecretResult(row as Record<string, unknown>);
}

export async function updateThirdPartyProviderPollCursor(
  client: ThirdPartyProviderAdapterMutationRpcClient,
  input: UpdateThirdPartyProviderPollCursorInput,
): Promise<ThirdPartyProviderConnection> {
  const parsedInput = UpdateThirdPartyProviderPollCursorInputSchema.parse(input);
  const { data, error } = await client.rpc("update_third_party_provider_poll_cursor", {
    p_connection_id: parsedInput.connectionId,
    p_cursor: parsedInput.cursor,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ThirdPartyProviderAdapterMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ThirdPartyProviderAdapterMutationError("invalid_response", "update_third_party_provider_poll_cursor returned no row");
  }
  return parseThirdPartyProviderConnection(data as Record<string, unknown>);
}

/** The provider's own webhook entry point. Never throws for a bad signature/malformed payload/unmapped vehicle/duplicate event -- see this module's own header. Only a genuine transport/serialization error throws. */
export async function ingestThirdPartyProviderWebhookEvent(
  client: ThirdPartyProviderAdapterMutationRpcClient,
  input: IngestThirdPartyProviderWebhookEventInput,
): Promise<IngestThirdPartyProviderWebhookEventResult> {
  const parsedInput = IngestThirdPartyProviderWebhookEventInputSchema.parse(input);
  const { data, error } = await client.rpc("ingest_third_party_provider_webhook_event", {
    p_connection_id: parsedInput.connectionId,
    p_client_key: parsedInput.clientKey,
    p_raw_payload: parsedInput.rawPayload,
    p_timestamp: parsedInput.timestamp,
    p_signature: parsedInput.signature,
  });
  if (error) {
    throw new ThirdPartyProviderAdapterMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new ThirdPartyProviderAdapterMutationError("invalid_response", "ingest_third_party_provider_webhook_event returned no row");
  }
  return parseIngestThirdPartyProviderWebhookEventResult(row as Record<string, unknown>);
}
