"use server";

/**
 * Platform Integrations (Supreme Admin) Server Actions -- user-directed extension of
 * CG-AUDIT-2026-09-02 A6/D4. Gated by `resolveSupremeAdminAccessForRequest` (the same
 * guard `supreme/tenants` and `supreme/helpdesk` already use) -- the real, enforcing
 * authority is `app.is_supreme_admin`, checked server-side inside
 * `app.set_platform_integration_secret`/`app.list_platform_integration_secrets`
 * themselves, never trusted from this layer alone.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { setPlatformIntegrationSecret, PlatformIntegrationSecretError, type PlatformIntegrationSecretsRpcClient } from "../../../../server/mutations/platform-integration-secrets.ts";

export interface PlatformIntegrationSecretActionState {
  readonly error: string | null;
}

/** The real Supabase client's own `rpc` overload set does not structurally satisfy PlatformIntegrationSecretsRpcClient's narrower literal-function-name interface -- identical adapter shape to document.ts's own toDocumentClient. */
function toPlatformIntegrationSecretsClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): PlatformIntegrationSecretsRpcClient {
  return client as unknown as PlatformIntegrationSecretsRpcClient;
}

const OK: PlatformIntegrationSecretActionState = { error: null };
const NO_ACCESS: PlatformIntegrationSecretActionState = { error: "You don't have Supreme Admin authority for this action." };

export async function setPlatformIntegrationSecretAction(_prevState: PlatformIntegrationSecretActionState, formData: FormData): Promise<PlatformIntegrationSecretActionState> {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") return NO_ACCESS;

  const secretKey = String(formData.get("secretKey") ?? "").trim();
  const secretValue = String(formData.get("secretValue") ?? "");
  const description = String(formData.get("description") ?? "").trim() || null;

  if (!secretKey) return { error: "A key name is required (lowercase, e.g. virustotal_api_key)." };
  if (!secretValue) return { error: "A non-empty secret value is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await setPlatformIntegrationSecret(toPlatformIntegrationSecretsClient(supabase), {
      secretKey,
      secretValue,
      description,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PlatformIntegrationSecretError) {
      if (error.code === "encryption_key_not_configured") {
        return { error: "This CargoGrid deployment has not had its integration-secret encryption key set up yet -- ask whoever manages the deployment's environment variables to provision app.integration_secrets_encryption_key, then try again." };
      }
      return { error: `Could not save this key: ${error.message}` };
    }
    throw error;
  }

  revalidatePath("/supreme/integrations");
  return OK;
}
