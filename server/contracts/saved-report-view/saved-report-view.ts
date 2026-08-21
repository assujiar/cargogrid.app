/**
 * Saved View and Configurable Report contract (IAE-004, Prompt 332). Mirrors
 * supabase/migrations/20260802030000_create_intelligence_saved_report_views.sql's
 * app.saved_report_views shape. A saved view stores no data of its own --
 * `filters` is the underlying app.report_types' own run parameters (IAE-002),
 * `columns`/`sort`/`grouping` are presentational-only.
 */

import { z } from "zod";

export const SAVED_REPORT_VIEW_SHARING_SCOPES = ["private", "tenant"] as const;
export const SavedReportViewSharingScopeSchema = z.enum(SAVED_REPORT_VIEW_SHARING_SCOPES);
export type SavedReportViewSharingScope = z.infer<typeof SavedReportViewSharingScopeSchema>;

/** Reuses the same generic flat-record shape IAE-002's own ReportParametersSchema established -- filters ARE the underlying report's own run parameters. */
export const SavedReportViewFiltersSchema = z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()]));
export type SavedReportViewFilters = z.input<typeof SavedReportViewFiltersSchema>;

export const SavedReportViewSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  reportTypeCode: z.string(),
  reportTypeVersionId: z.string().uuid().nullable(),
  ownerAuthUserId: z.string().uuid(),
  ownerLabel: z.string().nullable(),
  name: z.string(),
  description: z.string().nullable(),
  sharingScope: SavedReportViewSharingScopeSchema,
  columns: z.array(z.string()),
  filters: SavedReportViewFiltersSchema,
  sort: z.record(z.string(), z.unknown()),
  grouping: z.record(z.string(), z.unknown()),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type SavedReportView = z.infer<typeof SavedReportViewSchema>;

export function parseSavedReportView(row: Record<string, unknown>): SavedReportView {
  return SavedReportViewSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    reportTypeCode: row.report_type_code,
    reportTypeVersionId: row.report_type_version_id ?? null,
    ownerAuthUserId: row.owner_auth_user_id,
    ownerLabel: row.owner_label,
    name: row.name,
    description: row.description,
    sharingScope: row.sharing_scope,
    columns: row.columns ?? [],
    filters: row.filters ?? {},
    sort: row.sort ?? {},
    grouping: row.grouping ?? {},
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CreateSavedReportViewInputSchema = z.object({
  tenantId: z.string().uuid(),
  reportTypeCode: z.string().min(1),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  columns: z.array(z.string()).min(1),
  filters: SavedReportViewFiltersSchema.default({}),
  sort: z.record(z.string(), z.unknown()).default({}),
  grouping: z.record(z.string(), z.unknown()).default({}),
  sharingScope: SavedReportViewSharingScopeSchema.default("private"),
  idempotencyKey: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateSavedReportViewInput = z.input<typeof CreateSavedReportViewInputSchema>;

export const UpdateSavedReportViewInputSchema = z.object({
  viewId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  columns: z.array(z.string()).min(1),
  filters: SavedReportViewFiltersSchema.default({}),
  sort: z.record(z.string(), z.unknown()).default({}),
  grouping: z.record(z.string(), z.unknown()).default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateSavedReportViewInput = z.input<typeof UpdateSavedReportViewInputSchema>;

export const DeleteSavedReportViewInputSchema = z.object({
  viewId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DeleteSavedReportViewInput = z.input<typeof DeleteSavedReportViewInputSchema>;
