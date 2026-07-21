/**
 * Localization contract (PLT-119, CG-S6-PLT-016). Mirrors
 * supabase/migrations/20260717112000_create_localization.sql's
 * app.tenant_locale_versions/app.canonical_terms shape and the
 * app.create_tenant_locale_draft / app.set_tenant_locale_config /
 * app.publish_tenant_locale_version / app.discard_tenant_locale_draft /
 * app.rollback_tenant_locale_version / app.resolve_tenant_locale /
 * app.resolve_locale_context RPCs.
 */

import { z } from "zod";

export const SUPPORTED_LOCALES = ["id", "en"] as const;
export const LocaleSchema = z.enum(SUPPORTED_LOCALES);
export type Locale = z.infer<typeof LocaleSchema>;

export const SUPPORTED_TIMEZONES = ["Asia/Jakarta", "Asia/Makassar", "Asia/Jayapura", "UTC"] as const;
export const TimezoneSchema = z.enum(SUPPORTED_TIMEZONES);
export type Timezone = z.infer<typeof TimezoneSchema>;

export const SUPPORTED_CURRENCIES = ["IDR", "USD"] as const;
export const CurrencySchema = z.enum(SUPPORTED_CURRENCIES);
export type Currency = z.infer<typeof CurrencySchema>;

export const VERSION_STATUSES = ["draft", "published", "archived"] as const;
export const LocaleVersionStatusSchema = z.enum(VERSION_STATUSES);
export type LocaleVersionStatus = z.infer<typeof LocaleVersionStatusSchema>;

/** Terminology override values are plain text only (no HTML/script) -- keys are validated server-side against app.canonical_terms, not enumerable client-side (the catalogue grows per business-domain phase). */
export const TerminologyOverridesSchema = z.record(z.string(), z.string().min(1).max(80).regex(/^[^<>]*$/, "must not contain < or >"));
export type TerminologyOverrides = z.infer<typeof TerminologyOverridesSchema>;

export const CanonicalTermSchema = z.object({
  code: z.string(),
  category: z.string(),
  defaultLabelEn: z.string(),
  defaultLabelId: z.string(),
  createdAt: z.string(),
});
export type CanonicalTerm = z.infer<typeof CanonicalTermSchema>;

export const TenantLocaleVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: LocaleVersionStatusSchema,
  defaultLocale: LocaleSchema,
  defaultTimezone: TimezoneSchema,
  defaultCurrency: CurrencySchema,
  terminologyOverrides: z.record(z.string(), z.unknown()),
  effectiveFrom: z.string().nullable(),
  clonedFromVersionId: z.string().uuid().nullable(),
  rollbackOfVersionId: z.string().uuid().nullable(),
  createdBy: z.string().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string().nullable(),
  archivedAt: z.string().nullable(),
  archivedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TenantLocaleVersion = z.infer<typeof TenantLocaleVersionSchema>;

export const CreateTenantLocaleDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  createdBy: z.string().min(1),
});
export type CreateTenantLocaleDraftInput = z.infer<typeof CreateTenantLocaleDraftInputSchema>;

export const SetTenantLocaleConfigInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  defaultLocale: LocaleSchema.default("id"),
  defaultTimezone: TimezoneSchema.default("Asia/Jakarta"),
  defaultCurrency: CurrencySchema.default("IDR"),
  terminologyOverrides: TerminologyOverridesSchema.default({}),
  actorLabel: z.string().min(1),
});
export type SetTenantLocaleConfigInput = z.input<typeof SetTenantLocaleConfigInputSchema>;

export const PublishTenantLocaleVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishTenantLocaleVersionInput = z.input<typeof PublishTenantLocaleVersionInputSchema>;

export const DiscardTenantLocaleDraftInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type DiscardTenantLocaleDraftInput = z.input<typeof DiscardTenantLocaleDraftInputSchema>;

export const RollbackTenantLocaleVersionInputSchema = z.object({
  targetVersionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type RollbackTenantLocaleVersionInput = z.input<typeof RollbackTenantLocaleVersionInputSchema>;

export const ResolveLocaleContextInputSchema = z.object({
  tenantId: z.string().uuid(),
  userAuthUserId: z.string().uuid().nullable().default(null),
});
export type ResolveLocaleContextInput = z.input<typeof ResolveLocaleContextInputSchema>;

export const LOCALE_SOURCES = ["tenant", "default"] as const;
export const LocaleSourceSchema = z.enum(LOCALE_SOURCES);
export type LocaleSource = z.infer<typeof LocaleSourceSchema>;

export const LocaleContextSchema = z.object({
  tenantId: z.string().uuid(),
  source: LocaleSourceSchema,
  locale: LocaleSchema,
  timezone: TimezoneSchema,
  currency: CurrencySchema,
  terminologyOverrides: z.record(z.string(), z.unknown()),
});
export type LocaleContext = z.infer<typeof LocaleContextSchema>;

/** Maps a raw app.tenant_locale_versions row (snake_case) to this contract's camelCase shape. */
export function parseTenantLocaleVersion(row: Record<string, unknown>): TenantLocaleVersion {
  return TenantLocaleVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    versionNumber: row.version_number,
    status: row.status,
    defaultLocale: row.default_locale,
    defaultTimezone: row.default_timezone,
    defaultCurrency: row.default_currency,
    terminologyOverrides: row.terminology_overrides,
    effectiveFrom: row.effective_from,
    clonedFromVersionId: row.cloned_from_version_id,
    rollbackOfVersionId: row.rollback_of_version_id,
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

/** Maps a raw app.resolve_locale_context() row (snake_case) to this contract's camelCase shape. */
export function parseLocaleContext(row: Record<string, unknown>): LocaleContext {
  return LocaleContextSchema.parse({
    tenantId: row.tenant_id,
    source: row.source,
    locale: row.locale,
    timezone: row.timezone,
    currency: row.currency,
    terminologyOverrides: row.terminology_overrides,
  });
}

/** Maps a raw app.canonical_terms row (snake_case) to this contract's camelCase shape. */
export function parseCanonicalTerm(row: Record<string, unknown>): CanonicalTerm {
  return CanonicalTermSchema.parse({
    code: row.code,
    category: row.category,
    defaultLabelEn: row.default_label_en,
    defaultLabelId: row.default_label_id,
    createdAt: row.created_at,
  });
}
