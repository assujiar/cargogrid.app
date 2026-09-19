/**
 * Platform integration secrets contract (user-directed extension of
 * CG-AUDIT-2026-09-02 A6/D4, `20260908000000_create_platform_integration_secrets.sql`).
 * Mirrors the migration's `app.platform_integration_secrets` table and the
 * `app.set_platform_integration_secret` / `app.get_platform_integration_secret` /
 * `app.list_platform_integration_secrets` RPCs.
 *
 * There is deliberately no `secretValue`/`secretValueEncrypted` field on any type
 * here -- a platform secret is write-only from the application's own point of view
 * once saved (`set_platform_integration_secret` never returns it, and
 * `list_platform_integration_secrets` structurally cannot -- its own SQL `RETURNS
 * TABLE` shape has no such column). Only `getPlatformIntegrationSecret` in
 * `server/mutations/platform-integration-secrets.ts` ever resolves a decrypted
 * value, and that function is server_role-only, called exclusively from outbound
 * third-party integration code (e.g. the VirusTotal scan adapter), never from a
 * Server Action reachable by a browser session.
 */

import { z } from "zod";

export const PlatformIntegrationSecretSchema = z.object({
  secretKey: z.string(),
  description: z.string().nullable(),
  configuredByAuthUserId: z.string().uuid(),
  configuredAt: z.string(),
  rotatedAt: z.string().nullable(),
});
export type PlatformIntegrationSecret = z.infer<typeof PlatformIntegrationSecretSchema>;

export function parsePlatformIntegrationSecret(row: Record<string, unknown>): PlatformIntegrationSecret {
  return PlatformIntegrationSecretSchema.parse({
    secretKey: row.secret_key,
    description: row.description ?? null,
    configuredByAuthUserId: row.configured_by_auth_user_id,
    configuredAt: row.configured_at,
    rotatedAt: row.rotated_at ?? null,
  });
}

export const SetPlatformIntegrationSecretInputSchema = z.object({
  secretKey: z
    .string()
    .regex(/^[a-z][a-z0-9_]{2,63}$/, "must be lowercase snake_case, 3-64 characters, starting with a letter"),
  secretValue: z.string().min(1, "a non-empty secret value is required"),
  description: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetPlatformIntegrationSecretInput = z.infer<typeof SetPlatformIntegrationSecretInputSchema>;

export const GetPlatformIntegrationSecretInputSchema = z.object({
  secretKey: z.string(),
});
export type GetPlatformIntegrationSecretInput = z.infer<typeof GetPlatformIntegrationSecretInputSchema>;

export const ListPlatformIntegrationSecretsInputSchema = z.object({
  actorAuthUserId: z.string().uuid(),
});
export type ListPlatformIntegrationSecretsInput = z.infer<typeof ListPlatformIntegrationSecretsInputSchema>;
