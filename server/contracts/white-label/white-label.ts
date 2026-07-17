/**
 * White-label brand configuration contract (PLT-117, CG-S6-PLT-014). Mirrors
 * supabase/migrations/20260717090512_create_white_label.sql's
 * app.tenant_brand_versions shape and the app.create_tenant_brand_draft /
 * app.set_tenant_brand_tokens / app.publish_tenant_brand_version /
 * app.discard_tenant_brand_draft / app.rollback_tenant_brand_version /
 * app.evaluate_tenant_brand RPCs.
 */

import { z } from "zod";

export const BRAND_VERSION_STATUSES = ["draft", "published", "archived"] as const;
export const BrandVersionStatusSchema = z.enum(BRAND_VERSION_STATUSES);
export type BrandVersionStatus = z.infer<typeof BrandVersionStatusSchema>;

const HEX_COLOR_PATTERN = /^#[0-9a-fA-F]{6}$/;
const HTTPS_URL_PATTERN = /^https:\/\/[a-zA-Z0-9.-]+(\/[A-Za-z0-9._~%\-/]*)?$/;

/** RPD-019's fixed color-override surface -- exactly primary/secondary, nothing else. */
export const BrandTokensSchema = z
  .object({
    primary: z.string().regex(HEX_COLOR_PATTERN, "primary must be a #RRGGBB hex color").optional(),
    secondary: z.string().regex(HEX_COLOR_PATTERN, "secondary must be a #RRGGBB hex color").optional(),
  })
  .strict();
export type BrandTokens = z.infer<typeof BrandTokensSchema>;

const BrandAssetUrlSchema = z
  .string()
  .max(2048)
  .regex(HTTPS_URL_PATTERN, "asset URL must be a well-formed https:// URL")
  .nullable();

/** The fixed, whitelisted document/email template key set (Prompt 117 §24: "template variables are whitelisted, never arbitrary code"). */
export const DocumentTemplateRefsSchema = z
  .object({
    invoiceLetterheadUrl: BrandAssetUrlSchema.optional(),
    quotationLetterheadUrl: BrandAssetUrlSchema.optional(),
    emailFooterText: z.string().max(500).regex(/^[^<>]*$/, "must not contain < or >").optional(),
    emailHeaderText: z.string().max(500).regex(/^[^<>]*$/, "must not contain < or >").optional(),
  })
  .strict();
export type DocumentTemplateRefs = z.infer<typeof DocumentTemplateRefsSchema>;

export const TenantBrandVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: BrandVersionStatusSchema,
  tokens: BrandTokensSchema,
  logoAssetUrl: z.string().nullable(),
  emailSenderName: z.string().nullable(),
  emailLogoAssetUrl: z.string().nullable(),
  documentTemplateRefs: z.record(z.string(), z.unknown()),
  contrastValidated: z.boolean(),
  contrastReport: z.record(z.string(), z.unknown()).nullable(),
  clonedFromVersionId: z.string().uuid().nullable(),
  rollbackOfVersionId: z.string().uuid().nullable(),
  effectiveFrom: z.string().nullable(),
  createdBy: z.string().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string().nullable(),
  archivedAt: z.string().nullable(),
  archivedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TenantBrandVersion = z.infer<typeof TenantBrandVersionSchema>;

export const CreateTenantBrandDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateTenantBrandDraftInput = z.infer<typeof CreateTenantBrandDraftInputSchema>;

export const SetTenantBrandTokensInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  tokens: BrandTokensSchema.default({}),
  logoAssetUrl: z.string().nullable().default(null),
  emailSenderName: z.string().max(120).regex(/^[^<>]*$/, "must not contain < or >").nullable().default(null),
  emailLogoAssetUrl: z.string().nullable().default(null),
  documentTemplateRefs: DocumentTemplateRefsSchema.default({}),
  actorLabel: z.string().min(1),
});
export type SetTenantBrandTokensInput = z.input<typeof SetTenantBrandTokensInputSchema>;

export const PublishTenantBrandVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishTenantBrandVersionInput = z.input<typeof PublishTenantBrandVersionInputSchema>;

export const DiscardTenantBrandDraftInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type DiscardTenantBrandDraftInput = z.input<typeof DiscardTenantBrandDraftInputSchema>;

export const RollbackTenantBrandVersionInputSchema = z.object({
  targetVersionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type RollbackTenantBrandVersionInput = z.input<typeof RollbackTenantBrandVersionInputSchema>;

export const EvaluateTenantBrandInputSchema = z.object({
  tenantId: z.string().uuid(),
});
export type EvaluateTenantBrandInput = z.infer<typeof EvaluateTenantBrandInputSchema>;

export const BRAND_SOURCES = ["tenant", "default"] as const;
export const BrandSourceSchema = z.enum(BRAND_SOURCES);
export type BrandSource = z.infer<typeof BrandSourceSchema>;

export const EffectiveTenantBrandSchema = z.object({
  tenantId: z.string().uuid(),
  source: BrandSourceSchema,
  versionId: z.string().uuid().nullable(),
  versionNumber: z.number().int().positive().nullable(),
  tokens: BrandTokensSchema,
  logoAssetUrl: z.string().nullable(),
  emailSenderName: z.string().nullable(),
  emailLogoAssetUrl: z.string().nullable(),
  documentTemplateRefs: z.record(z.string(), z.unknown()),
  effectiveFrom: z.string().nullable(),
});
export type EffectiveTenantBrand = z.infer<typeof EffectiveTenantBrandSchema>;

/** Maps a raw app.tenant_brand_versions row (snake_case) to this contract's camelCase shape. */
export function parseTenantBrandVersion(row: Record<string, unknown>): TenantBrandVersion {
  return TenantBrandVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    versionNumber: row.version_number,
    status: row.status,
    tokens: row.tokens,
    logoAssetUrl: row.logo_asset_url,
    emailSenderName: row.email_sender_name,
    emailLogoAssetUrl: row.email_logo_asset_url,
    documentTemplateRefs: row.document_template_refs,
    contrastValidated: row.contrast_validated,
    contrastReport: row.contrast_report,
    clonedFromVersionId: row.cloned_from_version_id,
    rollbackOfVersionId: row.rollback_of_version_id,
    effectiveFrom: row.effective_from,
    createdBy: row.created_by,
    publishedBy: row.published_by,
    publishedAt: row.published_at,
    archivedAt: row.archived_at,
    archivedReason: row.archived_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.evaluate_tenant_brand() row (snake_case) to this contract's camelCase shape. */
export function parseEffectiveTenantBrand(row: Record<string, unknown>): EffectiveTenantBrand {
  return EffectiveTenantBrandSchema.parse({
    tenantId: row.tenant_id,
    source: row.source,
    versionId: row.version_id,
    versionNumber: row.version_number,
    tokens: row.tokens,
    logoAssetUrl: row.logo_asset_url,
    emailSenderName: row.email_sender_name,
    emailLogoAssetUrl: row.email_logo_asset_url,
    documentTemplateRefs: row.document_template_refs,
    effectiveFrom: row.effective_from,
  });
}
