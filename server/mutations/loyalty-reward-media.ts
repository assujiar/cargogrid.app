/**
 * Reward Catalogue media/terms file upload (ISS-2026-131 item 3). Reuses the
 * Platform Document/File Engine (PLT-128) directly -- app.
 * initiate_file_upload, service_role-only -- the exact same "call the RPC
 * name directly, classify into this capability's own error type" technique
 * server/mutations/customer-quote-request-attachment.ts already established
 * for CPL-302, rather than re-exporting document.ts's own
 * DocumentMutationError.
 *
 * uploadLoyaltyRewardMediaFile does NOT itself authorize the caller against
 * LYL:Create/Edit -- that per-action authority decision is the calling
 * Server Action's own job, checked through app.evaluate_permission BEFORE
 * this function is ever reached (see the Server Action for why that check
 * also has to run through the service-role client: app.evaluate_permission
 * is granted to service_role only, confirmed live, exactly like
 * app.initiate_file_upload itself). This function only fixes the two
 * capability-owned constants (documentTypeCode='reward_terms', recordType=
 * 'loyalty_reward') and forwards everything else.
 *
 * publishLoyaltyRewardTermsDocumentTypeDefinition composes three already-
 * shipped, already-tested primitives (createConfigDraft/setConfigItems/
 * publishDocumentTypeDefinition, PLT-121/PLT-128) into the one-time
 * per-tenant step app.resolve_document_type_definition requires before ANY
 * upload against 'reward_terms' can succeed -- confirmed live (2026-09-01,
 * project awdlicmwzdxquopwtcfd) that zero tenants have published ANY
 * `document:%` config_object yet, so every upload fails
 * document_type_not_configured until a tenant's own admin runs this. Config
 * values mirror scripts/db-tests/customer-loyalty-reward-catalogue.sql's own
 * already-live-tested 'reward_terms' definition exactly (PDF only, 10MB
 * ceiling, no special retention, internal classification, not legal-hold
 * eligible) -- terms/media documents attached to a reward, not financial or
 * legally-privileged records.
 *
 * Both functions require `client` to be the SERVICE-ROLE client:
 * app.initiate_file_upload, app.create_config_draft, app.set_config_items,
 * and app.publish_document_type_definition are ALL granted to service_role
 * only (never `authenticated`) -- these run inside a Server Action, never
 * client-side. The caller must already have verified, through the ordinary
 * RLS-scoped client, that the acting identity genuinely holds tenant-admin
 * portal access (and, for the upload path, LYL:Create/Edit) BEFORE calling
 * either function here.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  UploadLoyaltyRewardMediaInputSchema,
  PublishLoyaltyRewardTermsDocumentTypeInputSchema,
  LOYALTY_REWARD_TERMS_ALLOWED_MIME_TYPES,
  type UploadLoyaltyRewardMediaInput,
  type PublishLoyaltyRewardTermsDocumentTypeInput,
} from "../contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";
import { parseFile, type File as PlatformFile } from "../contracts/document/document.ts";
import type { ConfigVersion } from "../contracts/config/config.ts";
import { createConfigDraft, setConfigItems, ConfigMutationError, type ConfigMutationRpcClient } from "./config.ts";
import { publishDocumentTypeDefinition, DocumentMutationError, type DocumentMutationRpcClient } from "./document.ts";

export type LoyaltyRewardMediaMutationRpcClient = Pick<SupabaseClient, "rpc">;
export type PublishLoyaltyRewardTermsDocumentTypeRpcClient = ConfigMutationRpcClient & DocumentMutationRpcClient;

const KNOWN_MEDIA_MUTATION_ERROR_CODES = [
  "file_actor_unauthorized",
  "document_type_not_configured",
  "document_unsafe_filename",
  "document_mime_type_not_allowed",
  "document_file_too_large",
  "document_invalid_classification",
  "document_classification_too_weak",
] as const;
type KnownMediaMutationErrorCode = (typeof KNOWN_MEDIA_MUTATION_ERROR_CODES)[number];
export type LoyaltyRewardMediaMutationErrorCode = KnownMediaMutationErrorCode | "mutation_failed";

export class LoyaltyRewardMediaMutationError extends Error {
  readonly code: LoyaltyRewardMediaMutationErrorCode;

  constructor(code: LoyaltyRewardMediaMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyRewardMediaMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyRewardMediaMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (KNOWN_MEDIA_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownMediaMutationErrorCode) : "mutation_failed";
}

/**
 * Uploads one reward terms/media file's metadata. `recordId` is generic
 * (see the contract's own header) -- pass the reward's own id when editing
 * an existing draft, or the owning program's id when the reward itself does
 * not exist yet. Content bytes are never stored in this database (disclosed,
 * standing PLT-128 constraint, not unique to this capability) -- only
 * filename/MIME/size metadata is captured.
 */
export async function uploadLoyaltyRewardMediaFile(client: LoyaltyRewardMediaMutationRpcClient, input: UploadLoyaltyRewardMediaInput): Promise<PlatformFile> {
  const v = UploadLoyaltyRewardMediaInputSchema.parse(input);
  const { data, error } = await client.rpc("initiate_file_upload", {
    p_tenant_id: v.tenantId,
    p_document_type_code: "reward_terms",
    p_record_type: "loyalty_reward",
    p_record_id: v.recordId,
    p_original_filename: v.originalFilename,
    p_mime_type: v.mimeType,
    p_size_bytes: v.sizeBytes,
    p_classification: null,
    p_legal_hold: false,
    p_legal_hold_reason: null,
    p_shared_org_unit_ids: [],
    p_customer_account_ref: null,
    p_idempotency_key: v.idempotencyKey ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
  if (error) {
    throw new LoyaltyRewardMediaMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new LoyaltyRewardMediaMutationError("mutation_failed", "initiate_file_upload returned no row");
  }
  return parseFile(data as Record<string, unknown>);
}

// LOYALTY_REWARD_TERMS_ALLOWED_MIME_TYPES itself lives on the contract (re-
// exported below) so the admin UI's own <input accept> can import it without
// pulling this server-only mutation module into a Client Component bundle.
export { LOYALTY_REWARD_TERMS_ALLOWED_MIME_TYPES };
const LOYALTY_REWARD_TERMS_MAX_SIZE_BYTES = 10_485_760; // 10 MB, matches scripts/db-tests/customer-loyalty-reward-catalogue.sql's own live-tested definition.
const LOYALTY_REWARD_TERMS_RETENTION_CLASS = "none";
const LOYALTY_REWARD_TERMS_DEFAULT_CLASSIFICATION = "internal";
const LOYALTY_REWARD_TERMS_LEGAL_HOLD_ELIGIBLE = false;

/**
 * Publishes this tenant's own `document:reward_terms` definition, creating
 * the draft first if none is pending. Idempotent in the sense every
 * PLT-121 config version is: a fresh draft is created, populated, and
 * published every call -- republishing a definition that already exists is
 * a normal, safe "update the definition" operation (app.
 * publish_document_type_definition supersedes the prior published version),
 * never an error, so this is also how a tenant-admin would widen the
 * allowlist in the future without any code change.
 */
export async function publishLoyaltyRewardTermsDocumentTypeDefinition(
  client: PublishLoyaltyRewardTermsDocumentTypeRpcClient,
  input: PublishLoyaltyRewardTermsDocumentTypeInput,
): Promise<ConfigVersion> {
  const v = PublishLoyaltyRewardTermsDocumentTypeInputSchema.parse(input);
  try {
    const draft = await createConfigDraft(client, {
      configTypeCode: "document:reward_terms",
      tenantId: v.tenantId,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: v.actorAuthUserId,
      createdBy: v.actorLabel,
    });
    await setConfigItems(client, {
      versionId: draft.id,
      items: [
        { key: "allowed_mime_types", value: [...LOYALTY_REWARD_TERMS_ALLOWED_MIME_TYPES], canonicalRef: null },
        { key: "max_size_bytes", value: LOYALTY_REWARD_TERMS_MAX_SIZE_BYTES, canonicalRef: null },
        { key: "retention_class", value: LOYALTY_REWARD_TERMS_RETENTION_CLASS, canonicalRef: null },
        { key: "default_classification", value: LOYALTY_REWARD_TERMS_DEFAULT_CLASSIFICATION, canonicalRef: null },
        { key: "legal_hold_eligible", value: LOYALTY_REWARD_TERMS_LEGAL_HOLD_ELIGIBLE, canonicalRef: null },
      ],
      actorAuthUserId: v.actorAuthUserId,
      actorLabel: v.actorLabel,
    });
    return await publishDocumentTypeDefinition(client, {
      versionId: draft.id,
      actorAuthUserId: v.actorAuthUserId,
      effectiveFrom: null,
      actorLabel: v.actorLabel,
    });
  } catch (error) {
    if (error instanceof ConfigMutationError || error instanceof DocumentMutationError) {
      throw new LoyaltyRewardMediaMutationError("mutation_failed", error.message);
    }
    throw error;
  }
}
