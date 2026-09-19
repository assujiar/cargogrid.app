/**
 * Platform integration secrets mutation primitives (user-directed extension of
 * CG-AUDIT-2026-09-02 A6/D4,
 * `supabase/migrations/20260908000000_create_platform_integration_secrets.sql`).
 * Thin, typed wrappers around app.set_platform_integration_secret /
 * app.get_platform_integration_secret / app.list_platform_integration_secrets.
 *
 * `setPlatformIntegrationSecret` and `listPlatformIntegrationSecrets` are granted to
 * `authenticated` (Supreme Admin's own real session calls them, exactly like
 * `app.configure_platform_scheduled_task`/`app.list_platform_scheduled_tasks`) --
 * `getPlatformIntegrationSecret` is `service_role`-only, since only server-side
 * outbound-call code (never a browser session) may ever decrypt a stored value.
 */

import {
  SetPlatformIntegrationSecretInputSchema,
  GetPlatformIntegrationSecretInputSchema,
  ListPlatformIntegrationSecretsInputSchema,
  parsePlatformIntegrationSecret,
  type SetPlatformIntegrationSecretInput,
  type GetPlatformIntegrationSecretInput,
  type ListPlatformIntegrationSecretsInput,
  type PlatformIntegrationSecret,
} from "../contracts/platform-integration/platform-integration.ts";

export interface PlatformIntegrationSecretsRpcClient {
  rpc(
    fn: "set_platform_integration_secret" | "get_platform_integration_secret" | "list_platform_integration_secrets",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const PLATFORM_INTEGRATION_SECRET_KNOWN_ERROR_CODES = [
  "insufficient_authority",
  "platform_integration_secret_invalid_key",
  "platform_integration_secret_value_required",
  "encryption_key_not_configured",
] as const;
type KnownPlatformIntegrationSecretErrorCode = (typeof PLATFORM_INTEGRATION_SECRET_KNOWN_ERROR_CODES)[number];
export type PlatformIntegrationSecretErrorCode = KnownPlatformIntegrationSecretErrorCode | "mutation_failed" | "invalid_response";

export class PlatformIntegrationSecretError extends Error {
  readonly code: PlatformIntegrationSecretErrorCode;

  constructor(code: PlatformIntegrationSecretErrorCode, message: string) {
    super(message);
    this.name = "PlatformIntegrationSecretError";
    this.code = code;
  }
}

function classifyError(message: string): PlatformIntegrationSecretErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PLATFORM_INTEGRATION_SECRET_KNOWN_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownPlatformIntegrationSecretErrorCode)
    : "mutation_failed";
}

/** Supreme-Admin-only. Upsert on secretKey -- a second call for the same key rotates it. Never returns the plaintext value back to the caller (the caller already has it). */
export async function setPlatformIntegrationSecret(client: PlatformIntegrationSecretsRpcClient, input: SetPlatformIntegrationSecretInput): Promise<PlatformIntegrationSecret> {
  const parsedInput = SetPlatformIntegrationSecretInputSchema.parse(input);
  const { data, error } = await client.rpc("set_platform_integration_secret", {
    p_secret_key: parsedInput.secretKey,
    p_secret_value: parsedInput.secretValue,
    p_description: parsedInput.description ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new PlatformIntegrationSecretError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new PlatformIntegrationSecretError("invalid_response", "set_platform_integration_secret returned no row");
  }
  return parsePlatformIntegrationSecret(data as Record<string, unknown>);
}

/** service_role-only. Returns null (never throws) when the key has never been configured; throws encryption_key_not_configured (CG-AUDIT-2026-09-02 D4) when the underlying GUC is unset. Never call this from a Server Action reachable by a browser session -- only from server-side outbound third-party integration code. */
export async function getPlatformIntegrationSecret(client: PlatformIntegrationSecretsRpcClient, input: GetPlatformIntegrationSecretInput): Promise<string | null> {
  const parsedInput = GetPlatformIntegrationSecretInputSchema.parse(input);
  const { data, error } = await client.rpc("get_platform_integration_secret", {
    p_secret_key: parsedInput.secretKey,
  });
  if (error) {
    throw new PlatformIntegrationSecretError(classifyError(error.message), error.message);
  }
  return (data as string | null) ?? null;
}

/** Supreme-Admin-only. Never includes a value, encrypted or otherwise -- the RPC's own return shape structurally has no such column. */
export async function listPlatformIntegrationSecrets(client: PlatformIntegrationSecretsRpcClient, input: ListPlatformIntegrationSecretsInput): Promise<readonly PlatformIntegrationSecret[]> {
  const parsedInput = ListPlatformIntegrationSecretsInputSchema.parse(input);
  const { data, error } = await client.rpc("list_platform_integration_secrets", {
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new PlatformIntegrationSecretError(classifyError(error.message), error.message);
  }
  if (!Array.isArray(data)) {
    throw new PlatformIntegrationSecretError("invalid_response", "list_platform_integration_secrets did not return an array");
  }
  return data.map((row) => parsePlatformIntegrationSecret(row as Record<string, unknown>));
}
