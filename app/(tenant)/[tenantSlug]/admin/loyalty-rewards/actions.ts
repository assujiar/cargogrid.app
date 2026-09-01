"use server";

/**
 * Reward Catalogue admin Server Actions (CPL-320, CG-S13-CPL-022). Uses the
 * RLS-scoped `authenticated` client -- every RPC below is granted directly
 * to `authenticated` and performs its own LYL:Create/Edit/Configure
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses (e.g. app/(tenant)/[tenantSlug]/admin/loyalty-tiers/
 * actions.ts). Gated by resolveTenantAdminAccessForRequest (a coarse
 * tenant_admin portal-entry check) -- the real, per-action LYL:* authority
 * is enforced by each RPC itself, not by this guard.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { assertPermission, RbacDenialError } from "../../../../../server/policies/permission-check.ts";
import type { RbacRpcClient } from "../../../../../server/queries/rbac.ts";
import { createLoyaltyRewardDraft, updateLoyaltyRewardDraft, publishLoyaltyReward, pauseLoyaltyReward, resumeLoyaltyReward, archiveLoyaltyReward, LoyaltyRewardMutationError } from "../../../../../server/mutations/customer-portal-loyalty-rewards.ts";
import {
  uploadLoyaltyRewardMediaFile,
  publishLoyaltyRewardTermsDocumentTypeDefinition,
  LoyaltyRewardMediaMutationError,
  type LoyaltyRewardMediaMutationRpcClient,
  type PublishLoyaltyRewardTermsDocumentTypeRpcClient,
} from "../../../../../server/mutations/loyalty-reward-media.ts";
import type { LoyaltyRewardType } from "../../../../../server/contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";

/**
 * The real Supabase client's own `rpc` overload set does not structurally satisfy
 * these mutation modules' narrower literal-function-name interfaces -- identical
 * adapter shape to procurement/compliance/vendors/actions.ts's own toDocumentClient.
 */
function toMediaClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): LoyaltyRewardMediaMutationRpcClient & PublishLoyaltyRewardTermsDocumentTypeRpcClient {
  return client as unknown as LoyaltyRewardMediaMutationRpcClient & PublishLoyaltyRewardTermsDocumentTypeRpcClient;
}

export interface LoyaltyRewardAdminFormState {
  readonly error: string | null;
}

const INITIAL_STATE: LoyaltyRewardAdminFormState = { error: null };

function pathFor(tenantSlug: string, programId?: string): string {
  return programId ? `/${tenantSlug}/admin/loyalty-rewards?programId=${programId}` : `/${tenantSlug}/admin/loyalty-rewards`;
}

function readNullableText(formData: FormData, key: string): string | null {
  const raw = String(formData.get(key) ?? "").trim();
  return raw.length === 0 ? null : raw;
}

function readNullableNumber(formData: FormData, key: string): number | null {
  const raw = String(formData.get(key) ?? "").trim();
  if (raw.length === 0) return null;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function readDraftFields(formData: FormData): { rewardName: string; rewardType: string; description: string | null; termsText: string | null; minTierId: string | null; minPointsRequired: number | null; totalStock: number | null; internalCost: number | null; vendorRef: string | null; fileId: string | null } | { error: string } {
  const rewardName = String(formData.get("rewardName") ?? "").trim();
  const rewardType = String(formData.get("rewardType") ?? "").trim();
  if (rewardName.length === 0) return { error: "A reward name is required." };
  if (rewardType.length === 0) return { error: "A reward type is required." };

  const minPointsRequired = readNullableNumber(formData, "minPointsRequired");
  if (Number.isNaN(minPointsRequired)) return { error: "Minimum points required must be a number." };
  const totalStock = readNullableNumber(formData, "totalStock");
  if (Number.isNaN(totalStock)) return { error: "Total stock must be a whole number." };
  const internalCost = readNullableNumber(formData, "internalCost");
  if (Number.isNaN(internalCost)) return { error: "Internal cost must be a number." };

  return {
    rewardName,
    rewardType,
    description: readNullableText(formData, "description"),
    termsText: readNullableText(formData, "termsText"),
    minTierId: readNullableText(formData, "minTierId"),
    minPointsRequired,
    totalStock: totalStock === null ? null : Math.trunc(totalStock),
    internalCost,
    vendorRef: readNullableText(formData, "vendorRef"),
    fileId: readNullableText(formData, "fileId"),
  };
}

interface MediaFields {
  readonly originalFilename: string;
  readonly mimeType: string;
  readonly sizeBytes: number;
}

/** Present only when a real file was chosen in the new `<input type="file">` -- absent for the pasted-fileId-only path (unchanged, still supported below). */
function readMediaFields(formData: FormData): MediaFields | null {
  const originalFilename = readNullableText(formData, "mediaOriginalFilename");
  const mimeType = readNullableText(formData, "mediaMimeType");
  const sizeBytes = Number(formData.get("mediaSizeBytes") ?? 0);
  if (!originalFilename || !mimeType || !(sizeBytes > 0)) return null;
  return { originalFilename, mimeType, sizeBytes };
}

/**
 * Uploads a chosen reward media/terms file, returning the resulting `app.
 * files.id` to use in place of any pasted-text fallback. Re-checks LYL:
 * Create/Edit through app.evaluate_permission BEFORE the upload itself --
 * app.check_file_action_authority (the gate app.initiate_file_upload
 * actually enforces) only proves standing tenant membership, not LYL
 * authority, so without this pre-check any active tenant-admin-portal
 * member could create a real app.files row here even without LYL:Create/
 * Edit, regardless of what the downstream create/update RPC would later
 * reject. Both this check and the upload itself MUST run through the
 * service-role client: app.evaluate_permission and app.initiate_file_upload
 * are both granted to `service_role` only, never `authenticated` (confirmed
 * live and in lib/supabase/service-role.ts's own header) -- the "ordinary
 * RLS-scoped client" cannot call either one. The actor's real identity is
 * still the one resolved from the RLS-scoped resolveTenantAdminAccessForRequest
 * call the caller already made; it is only the RPC call itself that has to
 * go through service_role, exactly the same "explicit actor, service-role
 * execution" shape every other PLT-128 call site in this repository uses.
 */
async function uploadMediaFileOrThrow(tenantId: string, authUserId: string, action: "Create" | "Edit", recordId: string, media: MediaFields): Promise<string> {
  const client = createSupabaseServiceRoleClient();
  await assertPermission(client as unknown as RbacRpcClient, { authUserId, tenantId, resourceModuleCode: "LYL", action });
  const uploaded = await uploadLoyaltyRewardMediaFile(toMediaClient(client), {
    tenantId,
    recordId,
    originalFilename: media.originalFilename,
    mimeType: media.mimeType,
    sizeBytes: media.sizeBytes,
    idempotencyKey: null,
    actorAuthUserId: authUserId,
    actorLabel: authUserId,
  });
  return uploaded.id;
}

function describeMediaUploadError(error: unknown): string {
  if (error instanceof RbacDenialError) {
    return "You don't have permission to attach reward media (requires Loyalty Create/Edit authority).";
  }
  if (error instanceof LoyaltyRewardMediaMutationError) {
    if (error.code === "document_type_not_configured") {
      return "Reward media uploads are not enabled for this organization yet -- use \"Enable reward media uploads\" below, then try again.";
    }
    return `Could not upload the media file: ${error.message}`;
  }
  throw error;
}

export async function createLoyaltyRewardDraftAction(tenantSlug: string, programId: string, _prevState: LoyaltyRewardAdminFormState, formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const fields = readDraftFields(formData);
  if ("error" in fields) return fields;

  // A real chosen file overrides any pasted-text fileId (the pasted-id path
  // stays available below for anyone who already has one, e.g. from the
  // Document Center) -- see uploadMediaFileOrThrow's own header for why this
  // pre-checks LYL:Create through the service-role client before the upload.
  let fileId = fields.fileId;
  const media = readMediaFields(formData);
  if (media) {
    try {
      fileId = await uploadMediaFileOrThrow(access.tenant.id, access.authUserId, "Create", programId, media);
    } catch (error) {
      return { error: describeMediaUploadError(error) };
    }
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createLoyaltyRewardDraft(supabase, {
      tenantId: access.tenant.id,
      programId,
      rewardName: fields.rewardName,
      rewardType: fields.rewardType as LoyaltyRewardType,
      description: fields.description,
      termsText: fields.termsText,
      minTierId: fields.minTierId,
      minPointsRequired: fields.minPointsRequired,
      totalStock: fields.totalStock,
      internalCost: fields.internalCost,
      vendorRef: fields.vendorRef,
      fileId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not create the reward: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function updateLoyaltyRewardDraftAction(
  tenantSlug: string,
  programId: string,
  rewardId: string,
  expectedVersion: number,
  _prevState: LoyaltyRewardAdminFormState,
  formData: FormData,
): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const fields = readDraftFields(formData);
  if ("error" in fields) return fields;

  let fileId = fields.fileId;
  const media = readMediaFields(formData);
  if (media) {
    try {
      fileId = await uploadMediaFileOrThrow(access.tenant.id, access.authUserId, "Edit", rewardId, media);
    } catch (error) {
      return { error: describeMediaUploadError(error) };
    }
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateLoyaltyRewardDraft(supabase, {
      tenantId: access.tenant.id,
      rewardId,
      expectedVersion,
      rewardName: fields.rewardName,
      rewardType: fields.rewardType as LoyaltyRewardType,
      description: fields.description,
      termsText: fields.termsText,
      minTierId: fields.minTierId,
      minPointsRequired: fields.minPointsRequired,
      totalStock: fields.totalStock,
      internalCost: fields.internalCost,
      vendorRef: fields.vendorRef,
      fileId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not save the draft: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function publishLoyaltyRewardAction(tenantSlug: string, programId: string, rewardId: string, expectedVersion: number, _prevState: LoyaltyRewardAdminFormState, _formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await publishLoyaltyReward(supabase, { tenantId: access.tenant.id, rewardId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not publish: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function pauseLoyaltyRewardAction(tenantSlug: string, programId: string, rewardId: string, expectedVersion: number, _prevState: LoyaltyRewardAdminFormState, formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await pauseLoyaltyReward(supabase, { tenantId: access.tenant.id, rewardId, expectedVersion, reason: readNullableText(formData, "reason"), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not pause this reward: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function resumeLoyaltyRewardAction(tenantSlug: string, programId: string, rewardId: string, expectedVersion: number, _prevState: LoyaltyRewardAdminFormState, _formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await resumeLoyaltyReward(supabase, { tenantId: access.tenant.id, rewardId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not resume this reward: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function archiveLoyaltyRewardAction(tenantSlug: string, programId: string, rewardId: string, expectedVersion: number, _prevState: LoyaltyRewardAdminFormState, formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await archiveLoyaltyReward(supabase, { tenantId: access.tenant.id, rewardId, expectedVersion, reason: readNullableText(formData, "reason"), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not archive this reward: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

/**
 * One-time (re-runnable) per-tenant setup: publishes this tenant's own
 * `document:reward_terms` document-type definition, the precondition
 * app.resolve_document_type_definition requires before ANY reward media
 * upload can succeed. Gated by the identical resolveTenantAdminAccessForRequest
 * guard every other action in this file already uses -- no new authority
 * check invented for this one, matching the rest of this admin area.
 */
export async function enableLoyaltyRewardMediaUploadsAction(tenantSlug: string, programId: string, _prevState: LoyaltyRewardAdminFormState, _formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  try {
    await publishLoyaltyRewardTermsDocumentTypeDefinition(toMediaClient(createSupabaseServiceRoleClient()), {
      tenantId: access.tenant.id,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyRewardMediaMutationError) return { error: `Could not enable reward media uploads: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}
