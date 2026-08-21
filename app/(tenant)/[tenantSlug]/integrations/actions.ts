"use server";

/**
 * Integration Hub server actions (IAE-008, Prompt 336). Uses the
 * RLS-scoped `authenticated` client -- every app.* RPC below is
 * INTHUB:Configure-gated and performs its own permission check in-body,
 * mirroring every prior Phase 9 action's convention.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import {
  createIntegrationConnection,
  updateIntegrationConnectionConfig,
  rotateIntegrationConnectionCredential,
  setIntegrationConnectionStatus,
  recordIntegrationHealthCheck,
  IntegrationHubMutationError,
} from "../../../../server/mutations/integration-hub.ts";
import { IntegrationConnectionEnvironmentSchema, type IntegrationConnectionStatus } from "../../../../server/contracts/integration-hub/integration-hub.ts";

export interface IntegrationHubActionState {
  readonly error: string | null;
}

const OK: IntegrationHubActionState = { error: null };
const NO_ACCESS: IntegrationHubActionState = { error: "You don't have access to this organization's workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function parseJsonObject(raw: FormDataEntryValue | null): Record<string, unknown> {
  const text = String(raw ?? "").trim();
  if (!text) return {};
  const parsed: unknown = JSON.parse(text);
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("must be a JSON object");
  }
  return parsed as Record<string, unknown>;
}

export async function createIntegrationConnectionAction(tenantSlug: string, _prevState: IntegrationHubActionState, formData: FormData): Promise<IntegrationHubActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const adapterCode = String(formData.get("adapterCode") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const environmentRaw = String(formData.get("environment") ?? "production").trim();
  const ownerTeam = String(formData.get("ownerTeam") ?? "").trim() || null;
  const ownerEmail = String(formData.get("ownerEmail") ?? "").trim() || null;
  const runbookUrl = String(formData.get("runbookUrl") ?? "").trim() || null;
  const credentialValue = String(formData.get("credentialValue") ?? "").trim();

  const environmentParsed = IntegrationConnectionEnvironmentSchema.safeParse(environmentRaw);
  if (!environmentParsed.success) {
    return { error: "Environment must be sandbox or production." };
  }

  let config: Record<string, unknown>;
  try {
    config = parseJsonObject(formData.get("config"));
  } catch {
    return { error: "Config must be a valid JSON object." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createIntegrationConnection(supabase, {
      tenantId: access.tenant.id,
      adapterCode,
      name,
      environment: environmentParsed.data,
      ownerTeam,
      ownerEmail,
      runbookUrl,
      config,
      credentialValue,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof IntegrationHubMutationError) return { error: `Could not create this connection: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/integrations`);
  return OK;
}

export async function updateIntegrationConnectionConfigAction(
  tenantSlug: string,
  connectionId: string,
  _prevState: IntegrationHubActionState,
  formData: FormData,
): Promise<IntegrationHubActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const ownerTeam = String(formData.get("ownerTeam") ?? "").trim() || null;
  const ownerEmail = String(formData.get("ownerEmail") ?? "").trim() || null;
  const runbookUrl = String(formData.get("runbookUrl") ?? "").trim() || null;

  let config: Record<string, unknown>;
  try {
    config = parseJsonObject(formData.get("config"));
  } catch {
    return { error: "Config must be a valid JSON object." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateIntegrationConnectionConfig(supabase, { connectionId, config, ownerTeam, ownerEmail, runbookUrl, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof IntegrationHubMutationError) return { error: `Could not update this connection: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/integrations/${connectionId}`);
  return OK;
}

export async function rotateIntegrationConnectionCredentialAction(
  tenantSlug: string,
  connectionId: string,
  _prevState: IntegrationHubActionState,
  formData: FormData,
): Promise<IntegrationHubActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const newCredentialValue = String(formData.get("newCredentialValue") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await rotateIntegrationConnectionCredential(supabase, { connectionId, newCredentialValue, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof IntegrationHubMutationError) return { error: `Could not rotate this credential: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/integrations/${connectionId}`);
  return OK;
}

export async function setIntegrationConnectionStatusAction(
  tenantSlug: string,
  connectionId: string,
  status: IntegrationConnectionStatus,
  _prevState: IntegrationHubActionState,
  formData: FormData,
): Promise<IntegrationHubActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await setIntegrationConnectionStatus(supabase, { connectionId, status, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof IntegrationHubMutationError) return { error: `Could not change this connection's status: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/integrations/${connectionId}`);
  revalidatePath(`/${tenantSlug}/integrations`);
  return OK;
}

export async function recordIntegrationHealthCheckAction(
  tenantSlug: string,
  connectionId: string,
  status: "healthy" | "unhealthy",
  _prevState: IntegrationHubActionState,
  formData: FormData,
): Promise<IntegrationHubActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const detail = String(formData.get("detail") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await recordIntegrationHealthCheck(supabase, { connectionId, status, detail, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof IntegrationHubMutationError) return { error: `Could not record this health check: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/integrations/${connectionId}`);
  return OK;
}
