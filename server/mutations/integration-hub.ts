/**
 * Integration Hub mutation primitives (IAE-008, Prompt 336). Thin, typed
 * wrappers around app.create_integration_connection /
 * app.update_integration_connection_config /
 * app.rotate_integration_connection_credential /
 * app.set_integration_connection_status / app.record_integration_health_check
 * (supabase/migrations/20260803020000_create_intelligence_integration_hub.sql).
 * app.register_integration_adapter is deliberately NOT wrapped here --
 * service_role-only (a Supreme-Admin/ops seeding action), never callable
 * from a live end-user session.
 *
 * HDN-387 (HDN-BLK-023, Critical): setIntegrationConnectionStatus below now calls
 * app.request_integration_connection_status_change, not app.set_integration_
 * connection_status directly -- the latter's authenticated/service_role EXECUTE
 * grants were revoked in the same migration (20260819000000) since it independently
 * bypassed app.activate_enterprise_idp_connection's own IP-restriction/lockout/
 * step-up-MFA protections for enterprise SSO connections. The new entry point
 * refuses p_status='active' for an SSO adapter and delegates every other transition
 * unchanged.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateIntegrationConnectionInputSchema,
  UpdateIntegrationConnectionConfigInputSchema,
  RotateIntegrationConnectionCredentialInputSchema,
  SetIntegrationConnectionStatusInputSchema,
  RecordIntegrationHealthCheckInputSchema,
  parseIntegrationConnection,
  parseIntegrationHealthCheck,
  type CreateIntegrationConnectionInput,
  type UpdateIntegrationConnectionConfigInput,
  type RotateIntegrationConnectionCredentialInput,
  type SetIntegrationConnectionStatusInput,
  type RecordIntegrationHealthCheckInput,
  type IntegrationConnection,
  type IntegrationHealthCheck,
} from "../contracts/integration-hub/integration-hub.ts";

export type IntegrationHubMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const INTEGRATION_HUB_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "integration_adapter_unknown",
  "integration_connection_missing_name",
  "integration_connection_missing_credential",
  "integration_connection_unsafe_config",
  "integration_connection_not_found",
  "integration_connection_invalid_status",
  "integration_health_check_invalid_status",
  "enterprise_sso_activation_requires_specialized_wrapper",
] as const;
type KnownIntegrationHubMutationErrorCode = (typeof INTEGRATION_HUB_KNOWN_MUTATION_ERROR_CODES)[number];
export type IntegrationHubMutationErrorCode = KnownIntegrationHubMutationErrorCode | "mutation_failed" | "invalid_response";

export class IntegrationHubMutationError extends Error {
  readonly code: IntegrationHubMutationErrorCode;

  constructor(code: IntegrationHubMutationErrorCode, message: string) {
    super(message);
    this.name = "IntegrationHubMutationError";
    this.code = code;
  }
}

function classifyError(message: string): IntegrationHubMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (INTEGRATION_HUB_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownIntegrationHubMutationErrorCode)
    : "mutation_failed";
}

/** INTHUB:Configure-gated. Creates the connection plus its own fully isolated credential row in one transaction. */
export async function createIntegrationConnection(client: IntegrationHubMutationRpcClient, input: CreateIntegrationConnectionInput): Promise<IntegrationConnection> {
  const parsedInput = CreateIntegrationConnectionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_integration_connection", {
    p_tenant_id: parsedInput.tenantId,
    p_adapter_code: parsedInput.adapterCode,
    p_name: parsedInput.name,
    p_environment: parsedInput.environment,
    p_owner_team: parsedInput.ownerTeam,
    p_owner_email: parsedInput.ownerEmail,
    p_runbook_url: parsedInput.runbookUrl,
    p_config: parsedInput.config,
    p_credential_value: parsedInput.credentialValue,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_client_ip: parsedInput.clientIp ?? null,
  });
  if (error) {
    throw new IntegrationHubMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IntegrationHubMutationError("invalid_response", "create_integration_connection returned no row");
  }
  return parseIntegrationConnection(data as Record<string, unknown>);
}

/** INTHUB:Configure-gated. Non-secret config/owner/runbook fields only. */
export async function updateIntegrationConnectionConfig(client: IntegrationHubMutationRpcClient, input: UpdateIntegrationConnectionConfigInput): Promise<IntegrationConnection> {
  const parsedInput = UpdateIntegrationConnectionConfigInputSchema.parse(input);
  const { data, error } = await client.rpc("update_integration_connection_config", {
    p_connection_id: parsedInput.connectionId,
    p_config: parsedInput.config,
    p_owner_team: parsedInput.ownerTeam,
    p_owner_email: parsedInput.ownerEmail,
    p_runbook_url: parsedInput.runbookUrl,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IntegrationHubMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IntegrationHubMutationError("invalid_response", "update_integration_connection_config returned no row");
  }
  return parseIntegrationConnection(data as Record<string, unknown>);
}

/** INTHUB:Configure-gated. The caller supplies the new credential value directly; never returns or audits it. */
export async function rotateIntegrationConnectionCredential(
  client: IntegrationHubMutationRpcClient,
  input: RotateIntegrationConnectionCredentialInput,
): Promise<IntegrationConnection> {
  const parsedInput = RotateIntegrationConnectionCredentialInputSchema.parse(input);
  const { data, error } = await client.rpc("rotate_integration_connection_credential", {
    p_connection_id: parsedInput.connectionId,
    p_new_credential_value: parsedInput.newCredentialValue,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IntegrationHubMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IntegrationHubMutationError("invalid_response", "rotate_integration_connection_credential returned no row");
  }
  return parseIntegrationConnection(data as Record<string, unknown>);
}

/**
 * INTHUB:Configure-gated. Manual disable/re-enable/test-mode; never deletes connection
 * or health-check history. HDN-387 (HDN-BLK-023, Critical): calls app.request_
 * integration_connection_status_change, not the underlying app.set_integration_
 * connection_status core directly -- that core's own authenticated/service_role grant
 * was revoked in the same checkpoint. Reactivating an enterprise SSO connection through
 * this path is refused outright (enterprise_sso_activation_requires_specialized_
 * wrapper) -- use the dedicated SSO activation RPC instead.
 */
export async function setIntegrationConnectionStatus(client: IntegrationHubMutationRpcClient, input: SetIntegrationConnectionStatusInput): Promise<IntegrationConnection> {
  const parsedInput = SetIntegrationConnectionStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("request_integration_connection_status_change", {
    p_connection_id: parsedInput.connectionId,
    p_status: parsedInput.status,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IntegrationHubMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IntegrationHubMutationError("invalid_response", "request_integration_connection_status_change returned no row");
  }
  return parseIntegrationConnection(data as Record<string, unknown>);
}

/** INTHUB:Configure-gated. Records a real, caller-supplied health-check result ("Test connection"); auto-disables at 10 consecutive unhealthy checks. */
export async function recordIntegrationHealthCheck(client: IntegrationHubMutationRpcClient, input: RecordIntegrationHealthCheckInput): Promise<IntegrationHealthCheck> {
  const parsedInput = RecordIntegrationHealthCheckInputSchema.parse(input);
  const { data, error } = await client.rpc("record_integration_health_check", {
    p_connection_id: parsedInput.connectionId,
    p_status: parsedInput.status,
    p_detail: parsedInput.detail,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new IntegrationHubMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IntegrationHubMutationError("invalid_response", "record_integration_health_check returned no row");
  }
  return parseIntegrationHealthCheck(data as Record<string, unknown>);
}
